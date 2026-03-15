#!/bin/bash
# Patches author: KernelSU-Next Team @ Github
# Shell author: JackA1ltman <cs2dtzq@163.com>
# Ref: https://kernelsu-next.github.io/webpage/pages/how-to-integrate-for-non-gki.html
# Tested kernel versions: 5.4, 4.19, 4.14, 4.9, 4.4, 3.18
# 20250315

patch_files=(
    fs/exec.c
    fs/open.c
    fs/read_write.c
    fs/stat.c
    kernel/reboot.c
)

PATCH_LEVEL="1.0-next"
KERNEL_VERSION=$(head -n 3 Makefile | grep -E 'VERSION|PATCHLEVEL' | awk '{print $3}' | paste -sd '.')
FIRST_VERSION=$(echo "$KERNEL_VERSION" | awk -F '.' '{print $1}')
SECOND_VERSION=$(echo "$KERNEL_VERSION" | awk -F '.' '{print $2}')

echo "Current syscall patch version:$PATCH_LEVEL"

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

        if grep -q "ksu_handle_execveat" "drivers/kernelsu/core_hook.c" >/dev/null 2>&1; then
            echo "[+] Checked ksu_handle_execveat existed in KernelSU-Next!"

            sed -i '/^int do_execve(struct filename \*filename,/i\#ifdef CONFIG_KSU\n__attribute__((hot))\nextern int ksu_handle_execveat(int *fd, struct filename **filename_ptr,\n\t\t\t\tvoid *argv, void *envp, int *flags);\n#endif\n' fs/exec.c
            sed -i '0,/return do_execveat_common(AT_FDCWD, filename, argv, envp, 0);/{s/return do_execveat_common(AT_FDCWD, filename, argv, envp, 0);/#ifdef CONFIG_KSU\n\tksu_handle_execveat((int *)AT_FDCWD, \&filename, \&argv, \&envp, 0);\n#endif\n\treturn do_execveat_common(AT_FDCWD, filename, argv, envp, 0);/}' fs/exec.c
            awk '/return do_execveat_common\(AT_FDCWD, filename, argv, envp, 0\);/{count++; if(count==2){print "#ifdef CONFIG_KSU // 32-bit ksud and 32-on-64 support"; print "\tksu_handle_execveat((int *)AT_FDCWD, &filename, &argv, &envp, 0);"; print "#endif"}} {print}' fs/exec.c > fs/exec.c.tmp && mv fs/exec.c.tmp fs/exec.c
        else
            echo "[-] KernelSU-Next have no ksu_handle_execveat, Skipped."
        fi

        if grep -q "ksu_handle_execveat" "fs/exec.c"; then
            echo "[+] fs/exec.c Patched!"
            echo "[+] Count: $(grep -c "ksu_handle_execveat" "fs/exec.c")"
        else
            echo "[-] fs/exec.c patch failed for unknown reasons, please provide feedback in time."
        fi

        echo "======================================"
        ;;
    ## open.c
    fs/open.c)
        echo "======================================"

        if [ "$FIRST_VERSION" -lt 5 ] && [ "$SECOND_VERSION" -lt 19 ]; then
            sed -i '/^SYSCALL_DEFINE3(faccessat, int, dfd, const char __user \*, filename, int, mode)/i\#ifdef CONFIG_KSU\n__attribute__((hot))\nextern int ksu_handle_faccessat(int *dfd, const char __user **filename_user,\n\t\t\t\tint *mode, int *flags);\n#endif\n' fs/open.c
            sed -i '/if (mode & ~S_IRWXO)/i\#ifdef CONFIG_KSU\n\tksu_handle_faccessat(\&dfd, \&filename, \&mode, NULL);\n#endif' fs/open.c
        else
            sed -i '/^SYSCALL_DEFINE3(faccessat, int, dfd, const char __user \*, filename, int, mode)/i\#ifdef CONFIG_KSU\n__attribute__((hot))\nextern int ksu_handle_faccessat(int *dfd, const char __user **filename_user,\n\t\t\t\tint *mode, int *flags);\n#endif\n' fs/open.c
            sed -i '/return do_faccessat(dfd, filename, mode);/i\#ifdef CONFIG_KSU\n\tksu_handle_faccessat(\&dfd, \&filename, \&mode, NULL);\n#endif' fs/open.c
        fi

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
            echo "[+] Checked sys_read existed in KernelSU-Next!"

            if [ "$FIRST_VERSION" -lt 5 ] && [ "$SECOND_VERSION" -lt 19 ]; then
                sed -i '/^SYSCALL_DEFINE3(read, unsigned int, fd, char __user \*, buf, size_t, count)/i\#ifdef CONFIG_KSU\nextern bool ksu_vfs_read_hook __read_mostly;\nextern __attribute__((cold)) int ksu_handle_sys_read(unsigned int fd,\n\t\t\tchar __user **buf_ptr, size_t *count_ptr);\n#endif' fs/read_write.c
                sed -i '0,/if (f\.file) {/{s/if (f\.file) {/\n#ifdef CONFIG_KSU\n\tif (unlikely(ksu_vfs_read_hook))\n\t\tksu_handle_sys_read(fd, \&buf, \&count);\n#endif\n\tif (f.file) {/}' fs/read_write.c
            else
                sed -i '/^SYSCALL_DEFINE3(read, unsigned int, fd, char __user \*, buf, size_t, count)/i\#ifdef CONFIG_KSU\nextern bool ksu_vfs_read_hook __read_mostly;\nextern __attribute__((cold)) int ksu_handle_sys_read(unsigned int fd,\n\t\t\tchar __user **buf_ptr, size_t *count_ptr);\n#endif' fs/read_write.c
                sed -i '/return ksys_read(fd, buf, count);/i\#ifdef CONFIG_KSU\n\tif (unlikely(ksu_vfs_read_hook))\n\t\tksu_handle_sys_read(fd, \&buf, \&count);\n#endif' fs/read_write.c
            fi

            if grep -q "ksu_handle_sys_read" "fs/read_write.c"; then
                echo "[+] fs/read_write.c Patched!"
                echo "[+] Count: $(grep -c "ksu_handle_sys_read" "fs/read_write.c")"
            else
                echo "[-] fs/read_write.c patch failed for unknown reasons, please provide feedback in time."
            fi
        else
            echo "[-] KernelSU-Next have no sys_read, Skipped."
        fi

        echo "======================================"
        ;;
    ## stat.c
    fs/stat.c)
        echo "======================================"

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

        if grep -q "ksu_handle_sys_reboot" "drivers/kernelsu/core_hook.c" >/dev/null 2>&1; then
            echo "[+] Checked ksu_handle_sys_reboot existed in KernelSU-Next!"

            sed -i '/^SYSCALL_DEFINE4(reboot, int, magic1, int, magic2, unsigned int, cmd,/i\#ifdef CONFIG_KSU\nextern int ksu_handle_sys_reboot(int magic1, int magic2, unsigned int cmd,\n\t\t\t\tvoid __user **arg);\n#endif' kernel/reboot.c
            sed -i '/\tint ret = 0;/a\#ifdef CONFIG_KSU\n\tksu_handle_sys_reboot(magic1, magic2, cmd, \&arg);\n#endif' kernel/reboot.c

            if grep -q "ksu_handle_sys_reboot" "kernel/reboot.c"; then
                echo "[+] kernel/reboot.c Patched!"
                echo "[+] Count: $(grep -c "ksu_handle_sys_reboot" "kernel/reboot.c")"
            else
                echo "[-] kernel/reboot.c patch failed for unknown reasons, please provide feedback in time."
            fi
        elif grep -q "ksu_handle_sys_reboot" "drivers/kernelsu/supercalls.c" >/dev/null 2>&1; then
            echo "[+] Checked ksu_handle_sys_reboot existed in KernelSU-Next!"

            sed -i '/^SYSCALL_DEFINE4(reboot, int, magic1, int, magic2, unsigned int, cmd,/i\#ifdef CONFIG_KSU\nextern int ksu_handle_sys_reboot(int magic1, int magic2, unsigned int cmd,\n\t\t\t\tvoid __user **arg);\n#endif' kernel/reboot.c
            sed -i '/\tint ret = 0;/a\#ifdef CONFIG_KSU\n\tksu_handle_sys_reboot(magic1, magic2, cmd, \&arg);\n#endif' kernel/reboot.c

            if grep -q "ksu_handle_sys_reboot" "kernel/reboot.c"; then
                echo "[+] kernel/reboot.c Patched!"
                echo "[+] Count: $(grep -c "ksu_handle_sys_reboot" "kernel/reboot.c")"
            else
                echo "[-] kernel/reboot.c patch failed for unknown reasons, please provide feedback in time."
            fi
        else
            echo "[-] KernelSU-Next have no sys_reboot, Skipped."
        fi

        echo "======================================"
        ;;
    esac

done

