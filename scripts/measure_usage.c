#include <libproc.h>
#include <sys/resource.h>
#include <time.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec / 1e9; }
static double cpu(struct rusage_info_v4 *r) { return (r->ri_user_time + r->ri_system_time) / 1e9; }
static int usage(pid_t pid, struct rusage_info_v4 *r) { return proc_pid_rusage(pid, RUSAGE_INFO_V4, (rusage_info_t *)r); }

typedef struct { pid_t pid; uint64_t birth; } Seen;
int main(int argc, char **argv) {
    if (argc != 3) { fprintf(stderr, "Usage: measure-usage PID SECONDS\n"); return 2; }
    pid_t pid = (pid_t)atoi(argv[1]); double duration = atof(argv[2]);
    if (pid < 1 || duration < 2 || duration > 600) return 2;
    struct rusage_info_v4 first = {0}, last = {0};
    if (usage(pid, &first)) { perror("proc_pid_rusage"); return 3; }
    Seen seen[2048]; unsigned seenCount = 0;
    double start = now(), lastTick = start, lastCombined = cpu(&first) + (first.ri_child_user_time + first.ri_child_system_time)/1e9;
    double rssPeak = 0, fpPeak = 0, sumFP = 0, combinedPeak = 0;
    double traceTime[1024], traceCPU[1024], traceFP[1024]; unsigned traceCount = 0, samples = 0;
    while (1) {
        if (usage(pid, &last)) { fprintf(stderr, "Target process exited or became inaccessible.\n"); return 3; }
        double footprint = last.ri_phys_footprint / 1048576.0;
        double resident = last.ri_resident_size / 1048576.0;
        double combined = footprint, liveCPU = 0;
        pid_t children[128] = {0};
        proc_listchildpids(pid, children, sizeof(children));
        for (unsigned i = 0; i < 128; i++) {
            if (children[i] <= 0) continue;
            struct rusage_info_v4 child = {0};
            if (usage(children[i], &child)) continue;
            combined += child.ri_phys_footprint / 1048576.0; liveCPU += cpu(&child);
            int found = 0;
            for (unsigned j = 0; j < seenCount; j++) if (seen[j].pid == children[i] && seen[j].birth == child.ri_proc_start_abstime) found = 1;
            if (!found && seenCount < 2048) seen[seenCount++] = (Seen){children[i], child.ri_proc_start_abstime};
        }
        double stamp = now();
        double combinedCPU = cpu(&last) + (last.ri_child_user_time + last.ri_child_system_time)/1e9 + liveCPU;
        if (resident > rssPeak) rssPeak = resident;
        if (footprint > fpPeak) fpPeak = footprint;
        if (combined > combinedPeak) combinedPeak = combined;
        sumFP += footprint; samples++;
        if ((stamp - lastTick >= 1 || stamp-start >= duration) && traceCount < 1024) {
            traceTime[traceCount] = stamp-start;
            traceCPU[traceCount] = 100 * (combinedCPU > lastCombined ? combinedCPU-lastCombined : 0) / (stamp-lastTick);
            traceFP[traceCount++] = footprint;
            lastTick = stamp; lastCombined = combinedCPU;
        }
        if (stamp-start >= duration) break;
        usleep(50000);
    }
    double elapsed = now()-start;
    double ownCPU = 100*(cpu(&last)-cpu(&first))/elapsed;
    double childCPU = 100*((last.ri_child_user_time + last.ri_child_system_time)-(first.ri_child_user_time + first.ri_child_system_time))/1e9/elapsed;
    printf("{\"seconds\":%.3f,\"app_cpu_percent\":%.4f,\"app_and_helpers_cpu_percent\":%.4f,",elapsed,ownCPU,ownCPU+childCPU);
    printf("\"app_footprint_start_mib\":%.3f,\"app_footprint_end_mib\":%.3f,\"app_footprint_mean_mib\":%.3f,",first.ri_phys_footprint/1048576.0,last.ri_phys_footprint/1048576.0,sumFP/samples);
    printf("\"app_footprint_peak_mib\":%.3f,\"app_rss_peak_mib\":%.3f,\"app_and_helpers_footprint_peak_mib\":%.3f,",fpPeak,rssPeak,combinedPeak);
    printf("\"helpers_observed\":%u,\"wakeups_per_second\":%.3f,\"sample_period_ms\":50,\"trace\":[",seenCount,(last.ri_pkg_idle_wkups-first.ri_pkg_idle_wkups)/elapsed);
    for (unsigned i=0;i<traceCount;i++) printf("%s{\"t\":%.2f,\"cpu_percent\":%.4f,\"footprint_mib\":%.3f}",i?",":"",traceTime[i],traceCPU[i],traceFP[i]);
    printf("]}\n"); return 0;
}
