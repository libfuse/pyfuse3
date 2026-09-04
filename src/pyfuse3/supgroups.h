/*
 * supgroups.h
 *
 * Platform-independent interface to the supplementary group ids of a process
 *
 * This file is part of pyfuse3. This work may be distributed under the
 * terms of the GNU LGPL.
*/

#include <errno.h>
#include <sys/types.h>

/*
 * Darwin
 *
 * The process credentials are retrieved from the kernel with sysctl(3). The
 * kernel stores at most NGROUPS_MAX (16) group ids per process, which is the
 * same list that getgroups(2) returns for the calling process.
 */
#if PLATFORM == PLATFORM_DARWIN
#include <sys/sysctl.h>

/*
 * Store the supplementary group ids of process *pid* in *list*, which has
 * room for *size* entries. Return the number of group ids on success and -1
 * with errno set on error.
 */
static int get_sup_groups_p(pid_t pid, gid_t *list, int size) {
    struct kinfo_proc kp;
    size_t len = sizeof(kp);
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, pid };
    int i, ngroups;

    if (sysctl(mib, 4, &kp, &len, NULL, 0) != 0)
        return -1;
    if (len == 0) {
        errno = ESRCH;
        return -1;
    }
    ngroups = kp.kp_eproc.e_ucred.cr_ngroups;
    if (ngroups < 0 || ngroups > size) {
        errno = ERANGE;
        return -1;
    }
    for (i = 0; i < ngroups; i++)
        list[i] = kp.kp_eproc.e_ucred.cr_groups[i];
    return ngroups;
}

/*
 * Linux, FreeBSD & NetBSD
 *
 * Not implemented in C, pyfuse3 reads the group ids from /proc instead.
 */
#else

static int get_sup_groups_p(pid_t pid, gid_t *list, int size) {
    (void) pid;
    (void) list;
    (void) size;
    errno = ENOSYS;
    return -1;
}

#endif
