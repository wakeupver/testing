#!/bin/bash
# KernelSU-Next non-GKI manual kernel integration script
# Reference: https://kernelsu-next.github.io/webpage/pages/how-to-integrate-for-non-gki.html
# Credits: @sidex15, @maxsteeel, @rifsxd
# 20250601

PATCH_LEVEL="3.0"
KERNEL_VERSION=$(head -n 3 Makefile | grep -E 'VERSION|PATCHLEVEL' | awk '{print $3}' | paste -sd '.')

echo "======================================"
echo " KernelSU-Next non-GKI Patch v${PATCH_LEVEL}"
echo " Kernel: ${KERNEL_VERSION}"
echo "======================================"

patch_files=(
    fs/exec.c
    fs/open.c
    fs/read_write.c
    fs/stat.c
    kernel/reboot.c
    security/selinux/hooks.c
)

for i in "${patch_files[@]}"; do

    if [ ! -f "$i" ]; then
        echo "[-] $i: file not found, skipping."
        echo "======================================"
        continue
    fi

    if grep -q "ksu_handle" "$i"; then
        echo "[-] Warning: $i already contains KernelSU hooks"
        echo "[+] Existing hooks:"
        grep -n "ksu_handle" "$i"
        echo "======================================"
        continue
    fi

    echo "[*] Patching $i ..."

    case $i in

    # ----------------------------------------------------------------
    # fs/exec.c
    # Hook: ksu_handle_execveat
    #   - Extern declaration before int do_execve(...)
    #   - Call inside do_execve + compat_do_execve before return
    # ----------------------------------------------------------------
    fs/exec.c)
        sed -i '/^int do_execve(struct filename \*filename,/i\
#ifdef CONFIG_KSU\
__attribute__((hot))\
extern int ksu_handle_execveat(int *fd, struct filename **filename_ptr,\
\t\t\t\tvoid *argv, void *envp, int *flags);\
#endif\
' fs/exec.c

        # Inserts before ALL occurrences — covers do_execve and compat_do_execve
        sed -i '/return do_execveat_common(AT_FDCWD, filename, argv, envp, 0);/i\
#ifdef CONFIG_KSU\
\tksu_handle_execveat((int *)AT_FDCWD, \&filename, \&argv, \&envp, 0);\
#endif' fs/exec.c

        if grep -q "ksu_handle_execveat" "fs/exec.c"; then
            echo "[+] fs/exec.c Patched!"
            echo "[+] Count: $(grep -c "ksu_handle_execveat" "fs/exec.c")"
        else
            echo "[-] fs/exec.c patch FAILED."
        fi
        echo "======================================"
        ;;

    # ----------------------------------------------------------------
    # fs/open.c
    # Hook: ksu_handle_faccessat
    #   - Extern declaration before SYSCALL_DEFINE3(faccessat,...)
    #   - Call before "if (mode & ~S_IRWXO)"
    # ----------------------------------------------------------------
    fs/open.c)
        sed -i '/^SYSCALL_DEFINE3(faccessat, int, dfd, const char __user \*, filename, int, mode)/i\
#ifdef CONFIG_KSU\
__attribute__((hot))\
extern int ksu_handle_faccessat(int *dfd, const char __user **filename_user,\
\t\t\t\tint *mode, int *flags);\
#endif\
' fs/open.c

        sed -i '/if (mode & ~S_IRWXO)/i\
#ifdef CONFIG_KSU\
\tksu_handle_faccessat(\&dfd, \&filename, \&mode, NULL);\
#endif\
' fs/open.c

        if grep -q "ksu_handle_faccessat" "fs/open.c"; then
            echo "[+] fs/open.c Patched!"
            echo "[+] Count: $(grep -c "ksu_handle_faccessat" "fs/open.c")"
        else
            echo "[-] fs/open.c patch FAILED."
        fi
        echo "======================================"
        ;;

    # ----------------------------------------------------------------
    # fs/read_write.c
    # Hook: ksu_handle_sys_read
    #   - Extern declarations before SYSCALL_DEFINE3(read,...)
    #   - Call inside SYSCALL_DEFINE3(read) before first "if (f.file) {"
    # ----------------------------------------------------------------
    fs/read_write.c)
        sed -i '/^SYSCALL_DEFINE3(read, unsigned int, fd, char __user \*, buf, size_t, count)/i\
#ifdef CONFIG_KSU\
extern bool ksu_vfs_read_hook __read_mostly;\
extern __attribute__((cold)) int ksu_handle_sys_read(unsigned int fd,\
\t\t\t\tchar __user **buf_ptr, size_t *count_ptr);\
#endif\
' fs/read_write.c

        sed -i '0,/if (f\.file) {/{s/if (f\.file) {/\n#ifdef CONFIG_KSU\n\tif (unlikely(ksu_vfs_read_hook))\n\t\tksu_handle_sys_read(fd, \&buf, \&count);\n#endif\n\tif (f.file) {/}' fs/read_write.c

        if grep -q "ksu_handle_sys_read" "fs/read_write.c"; then
            echo "[+] fs/read_write.c Patched!"
            echo "[+] Count: $(grep -c "ksu_handle_sys_read" "fs/read_write.c")"
        else
            echo "[-] fs/read_write.c patch FAILED."
        fi
        echo "======================================"
        ;;

    # ----------------------------------------------------------------
    # fs/stat.c
    # Hook: ksu_handle_stat
    #   - Extern declaration before #if !defined(__ARCH_WANT_STAT64)...
    #   - Call before "error = vfs_fstatat(...)" (newfstatat)
    # ----------------------------------------------------------------
    fs/stat.c)
        sed -i '/#if !defined(__ARCH_WANT_STAT64) || defined(__ARCH_WANT_SYS_NEWFSTATAT)/i\
#ifdef CONFIG_KSU\
__attribute__((hot))\
extern int ksu_handle_stat(int *dfd, const char __user **filename_user,\
\t\t\t\tint *flags);\
#endif\
' fs/stat.c

        sed -i '/error = vfs_fstatat(dfd, filename, \&stat, flag);/i\
#ifdef CONFIG_KSU\
\tksu_handle_stat(\&dfd, \&filename, \&flag);\
#endif\
' fs/stat.c

        if grep -q "ksu_handle_stat" "fs/stat.c"; then
            echo "[+] fs/stat.c Patched!"
            echo "[+] Count: $(grep -c "ksu_handle_stat" "fs/stat.c")"
        else
            echo "[-] fs/stat.c patch FAILED."
        fi
        echo "======================================"
        ;;

    # ----------------------------------------------------------------
    # kernel/reboot.c
    # Hook: ksu_handle_sys_reboot
    #   - Extern declaration before SYSCALL_DEFINE4(reboot,...)
    #   - Call before "/* We only trust the superuser... */"
    # ----------------------------------------------------------------
    kernel/reboot.c)
        sed -i '/^SYSCALL_DEFINE4(reboot, int, magic1, int, magic2, unsigned int, cmd,/i\
#ifdef CONFIG_KSU\
extern int ksu_handle_sys_reboot(int magic1, int magic2, unsigned int cmd, void __user **arg);\
#endif\
' kernel/reboot.c

        sed -i '/\/\* We only trust the superuser with rebooting the system\. \*\//i\
#ifdef CONFIG_KSU\
\tksu_handle_sys_reboot(magic1, magic2, cmd, \&arg);\
#endif\
' kernel/reboot.c

        if grep -q "ksu_handle_sys_reboot" "kernel/reboot.c"; then
            echo "[+] kernel/reboot.c Patched!"
            echo "[+] Count: $(grep -c "ksu_handle_sys_reboot" "kernel/reboot.c")"
        else
            echo "[-] kernel/reboot.c patch FAILED."
        fi
        echo "======================================"
        ;;

    ## selinux/hooks.c
    security/selinux/hooks.c)
        if grep -q "security_secid_to_secctx" "security/selinux/hooks.c" >/dev/null 2>&1; then
            echo "[-] Detected security_secid_to_secctx existed, security/selinux/hooks.c Patched!"
        elif [ "$FIRST_VERSION" -lt 5 ] && [ "$SECOND_VERSION" -lt 10 ]; then
            sed -i '/int nnp = (bprm->unsafe & LSM_UNSAFE_NO_NEW_PRIVS);/i\#ifdef CONFIG_KSU\n    static u32 ksu_sid;\n    char *secdata;\n#endif' security/selinux/hooks.c
            sed -i '/if (!nnp && !nosuid)/i\#ifdef CONFIG_KSU\n    int error;\n    u32 seclen;\n#endif' security/selinux/hooks.c
            sed -i '/return 0; \/\* No change in credentials \*\//a\\n#ifdef CONFIG_KSU\n    if (!ksu_sid)\n        security_secctx_to_secid("u:r:su:s0", strlen("u:r:su:s0"), &ksu_sid);\n\n    error = security_secid_to_secctx(old_tsec->sid, &secdata, &seclen);\n    if (!error) {\n        rc = strcmp("u:r:init:s0", secdata);\n        security_release_secctx(secdata, seclen);\n        if (rc == 0 && new_tsec->sid == ksu_sid)\n            return 0;\n    }\n#endif' security/selinux/hooks.c

            if grep -q "security_secid_to_secctx" "security/selinux/hooks.c"; then
                echo "[+] security/selinux/hooks.c Patched!"
                echo "[+] Count: $(grep -c "security_secid_to_secctx" "security/selinux/hooks.c")"
            else
                echo "[-] security/selinux/hooks.c patch failed for unknown reasons, please provide feedback in time."
            fi
        else
            echo "[-] Kernel needn't selinux fix, Skipped."
        fi

        echo "======================================"
        ;;        

    esac

done

echo "KernelSU-Next non-GKI integration complete."
