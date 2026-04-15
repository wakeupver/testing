#!/bin/bash
# Patches author: backslashxx @ Github
# Shell author: JackA1ltman <cs2dtzq@163.com>
# Tested kernel versions: 5.4, 4.19, 4.14, 4.9, 4.4, 3.18
# Updated for KernelSU Next (https://kernelsu-next.github.io/webpage/pages/how-to-integrate-for-non-gki.html)
# 20250415

patch_files=(
    fs/exec.c
    fs/open.c
    fs/read_write.c
    fs/stat.c
    kernel/reboot.c
    security/selinux/hooks.c
)

PATCH_LEVEL="2.0"
KERNEL_VERSION=$(head -n 3 Makefile | grep -E 'VERSION|PATCHLEVEL' | awk '{print $3}' | paste -sd '.')
FIRST_VERSION=$(echo "$KERNEL_VERSION" | awk -F '.' '{print $1}')
SECOND_VERSION=$(echo "$KERNEL_VERSION" | awk -F '.' '{print $2}')

echo "Current syscall patch version: $PATCH_LEVEL"

for i in "${patch_files[@]}"; do

    if grep -q "ksu_handle" "$i"; then
        echo "[-] Warning: $i contains KernelSU"
        echo "[+] Code in here:"
        grep -n "ksu_handle" "$i"
        echo "[-] End of file."
        echo "======================================"
        continue
    fi

    case $i in

    # fs/ changes
    ## exec.c
    fs/exec.c)
        echo "======================================"

        # Insert extern declaration before do_execve
        sed -i '/^int do_execve(struct filename \*filename,/i\#ifdef CONFIG_KSU\n__attribute__((hot))\nextern int ksu_handle_execveat(int *fd, struct filename **filename_ptr,\n\t\t\tvoid *argv, void *envp, int *flags);\n#endif\n' fs/exec.c

        # Insert hook in do_execve and compat_do_execve (matches all occurrences)
        # This covers: do_execve (64-bit) and compat_do_execve (32-bit / 32-on-64 support)
        sed -i '/return do_execveat_common(AT_FDCWD, filename, argv, envp, 0);/i\#ifdef CONFIG_KSU\n\tksu_handle_execveat((int *)AT_FDCWD, \&filename, \&argv, \&envp, 0);\n#endif' fs/exec.c

        if grep -q "ksu_handle_execveat" "fs/exec.c"; then
            EXEC_COUNT=$(grep -c "ksu_handle_execveat" "fs/exec.c")
            echo "[+] fs/exec.c Patched!"
            echo "[+] Count: $EXEC_COUNT"
            # compat_do_execve adds 2 extra occurrences (extern + hook)
            if [ "$EXEC_COUNT" -ge 4 ]; then
                echo "[+] compat_do_execve also patched (32-bit / 32-on-64 support)"
            else
                echo "[-] compat_do_execve not found or not patched (may not exist on this kernel)"
            fi
        else
            echo "[-] fs/exec.c patch failed for unknown reasons, please provide feedback in time."
        fi

        echo "======================================"
        ;;

    ## open.c
    fs/open.c)
        echo "======================================"

        sed -i '/^SYSCALL_DEFINE3(faccessat, int, dfd, const char __user \*, filename, int, mode)/i\#ifdef CONFIG_KSU\n__attribute__((hot))\nextern int ksu_handle_faccessat(int *dfd, const char __user **filename_user,\n\t\t\t\tint *mode, int *flags);\n#endif\n' fs/open.c
        sed -i '/if (mode & ~S_IRWXO)/i\#ifdef CONFIG_KSU\n\tksu_handle_faccessat(\&dfd, \&filename, \&mode, NULL);\n#endif' fs/open.c

        if grep -q "ksu_handle_faccessat" "fs/open.c"; then
            echo "[+] fs/open.c Patched!"
            echo "[+] Count: $(grep -c "ksu_handle_faccessat" "fs/open.c")"
        else
            echo "[-] fs/open.c patch failed for unknown reasons, please provide feedback in time."
        fi

        echo "======================================"
        ;;

    ## read_write.c
    fs/read_write.c)
        echo "======================================"

        if grep -q "sys_read" "drivers/kernelsu/arch.h" >/dev/null 2>&1; then
            sed -i '/^SYSCALL_DEFINE3(read, unsigned int, fd, char __user \*, buf, size_t, count)/i\#ifdef CONFIG_KSU\nextern bool ksu_vfs_read_hook __read_mostly;\nextern __attribute__((cold)) int ksu_handle_sys_read(unsigned int fd,\n\t\t\tchar __user **buf_ptr, size_t *count_ptr);\n#endif' fs/read_write.c
            sed -i '0,/if (f\.file) {/{s/if (f\.file) {/\n#ifdef CONFIG_KSU\n\tif (unlikely(ksu_vfs_read_hook))\n\t\tksu_handle_sys_read(fd, \&buf, \&count);\n#endif\n\tif (f.file) {/}' fs/read_write.c

            if grep -q "ksu_handle_sys_read" "fs/read_write.c"; then
                echo "[+] fs/read_write.c Patched!"
                echo "[+] Count: $(grep -c "ksu_handle_sys_read" "fs/read_write.c")"
            else
                echo "[-] fs/read_write.c patch failed for unknown reasons, please provide feedback in time."
            fi
        else
            echo "[-] KernelSU Next has no sys_read hook for this config, Skipped."
        fi

        echo "======================================"
        ;;

    ## stat.c
    fs/stat.c)
        echo "======================================"

        # Insert extern declaration between SYSCALL_DEFINE2(newlstat) and #if !defined(__ARCH_WANT_STAT64)
        # per KernelSU Next docs diff (@@ -353,6 +353,10 @@ SYSCALL_DEFINE2(newlstat ...)
        sed -i '/^#if !defined(__ARCH_WANT_STAT64) || defined(__ARCH_WANT_SYS_NEWFSTATAT)/i\#ifdef CONFIG_KSU\n__attribute__((hot))\nextern int ksu_handle_stat(int *dfd, const char __user **filename_user,\n\t\t\t\tint *flags);\n#endif\n' fs/stat.c
        sed -i '/error = vfs_fstatat(dfd, filename, \&stat, flag);/i\#ifdef CONFIG_KSU\n\tksu_handle_stat(\&dfd, \&filename, \&flag);\n#endif' fs/stat.c

        if grep -q "ksu_handle_stat" "fs/stat.c"; then
            echo "[+] fs/stat.c Patched!"
            echo "[+] Count: $(grep -c "ksu_handle_stat" "fs/stat.c")"
        else
            echo "[-] fs/stat.c patch failed for unknown reasons, please provide feedback in time."
        fi

        echo "======================================"
        ;;

    # kernel/ changes
    ## kernel/reboot.c
    kernel/reboot.c)
        echo "======================================"

        if grep -q "ksu_handle_sys_reboot" "drivers/kernelsu/core_hook.c" >/dev/null 2>&1 || \
           grep -q "ksu_handle_sys_reboot" "drivers/kernelsu/supercalls.c" >/dev/null 2>&1; then
            echo "[+] Checked ksu_handle_sys_reboot existed in KernelSU Next!"

            sed -i '/SYSCALL_DEFINE4(reboot, int, magic1, int, magic2, unsigned int, cmd,/i\#ifdef CONFIG_KSU\nextern int ksu_handle_sys_reboot(int magic1, int magic2, unsigned int cmd, void __user **arg);\n#endif\n' kernel/reboot.c
            sed -i '/int ret = 0;/a\#ifdef CONFIG_KSU\n\tksu_handle_sys_reboot(magic1, magic2, cmd, \&arg);\n#endif' kernel/reboot.c

            if grep -q "ksu_handle_sys_reboot" "kernel/reboot.c"; then
                echo "[+] kernel/reboot.c Patched!"
                echo "[+] Count: $(grep -c "ksu_handle_sys_reboot" "kernel/reboot.c")"
            else
                echo "[-] kernel/reboot.c patch failed for unknown reasons, please provide feedback in time."
            fi
        else
            echo "[-] KernelSU Next has no sys_reboot hook for this config, Skipped."
        fi

        echo "======================================"
        ;;

    ## selinux/hooks.c
    security/selinux/hooks.c)
        echo "======================================"

        if grep -q "security_secid_to_secctx" "security/selinux/hooks.c" >/dev/null 2>&1; then
            echo "[-] Detected security_secid_to_secctx existed, security/selinux/hooks.c already patched!"
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
            echo "[-] Kernel does not need selinux fix, Skipped."
        fi

        echo "======================================"
        ;;

    esac

done
