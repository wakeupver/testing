#!/bin/bash

PATCH_LEVEL="ksu_manual_doc"

patch_files=(
fs/exec.c
fs/open.c
fs/read_write.c
fs/stat.c
kernel/reboot.c
)

echo "KernelSU manual integration patch"
echo "Patch level: $PATCH_LEVEL"
echo "================================"

for i in "${patch_files[@]}"; do

if [ ! -f "$i" ]; then
    echo "[-] $i not found, skipped"
    continue
fi

if grep -q "ksu_handle" "$i"; then
    echo "[-] $i already patched"
    grep -n "ksu_handle" "$i"
    echo "--------------------------------"
    continue
fi

case $i in

# ------------------------------------------------
# exec.c
# ------------------------------------------------
fs/exec.c)

echo "[*] patching fs/exec.c"

sed -i '/static int do_execveat_common/i\
#ifdef CONFIG_KSU\
extern bool ksu_execveat_hook __read_mostly;\
extern int ksu_handle_execveat(int *fd, struct filename **filename_ptr, void *argv,\
        void *envp, int *flags);\
extern int ksu_handle_execveat_sucompat(int *fd, struct filename **filename_ptr,\
        void *argv, void *envp, int *flags);\
#endif\
' fs/exec.c

sed -i '/return __do_execve_file/i\
#ifdef CONFIG_KSU\
    if (unlikely(ksu_execveat_hook))\
        ksu_handle_execveat(&fd, &filename, &argv, &envp, &flags);\
    else\
        ksu_handle_execveat_sucompat(&fd, &filename, &argv, &envp, &flags);\
#endif\
' fs/exec.c

;;

# ------------------------------------------------
# open.c
# ------------------------------------------------
fs/open.c)

echo "[*] patching fs/open.c"

sed -i '/do_faccessat/i\
#ifdef CONFIG_KSU\
extern int ksu_handle_faccessat(int *dfd,\
        const char __user **filename_user,\
        int *mode,\
        int *flags);\
#endif\
' fs/open.c

sed -i '/return do_faccessat/i\
#ifdef CONFIG_KSU\
    ksu_handle_faccessat(&dfd, &filename, &mode, NULL);\
#endif\
' fs/open.c

;;

# ------------------------------------------------
# read_write.c
# ------------------------------------------------
fs/read_write.c)

echo "[*] patching fs/read_write.c"

sed -i '/vfs_read/i\
#ifdef CONFIG_KSU\
extern bool ksu_vfs_read_hook __read_mostly;\
extern int ksu_handle_sys_read(unsigned int fd,\
        char __user **buf_ptr,\
        size_t *count_ptr);\
#endif\
' fs/read_write.c

sed -i '/return ret;/i\
#ifdef CONFIG_KSU\
    if (unlikely(ksu_vfs_read_hook))\
        ksu_handle_sys_read(fd, &buf, &count);\
#endif\
' fs/read_write.c

;;

# ------------------------------------------------
# stat.c
# ------------------------------------------------
fs/stat.c)

echo "[*] patching fs/stat.c"

sed -i '/vfs_fstatat/i\
#ifdef CONFIG_KSU\
extern int ksu_handle_stat(int *dfd,\
        const char __user **filename_user,\
        int *flags);\
#endif\
' fs/stat.c

sed -i '/int vfs_fstatat/a\
#ifdef CONFIG_KSU\
    ksu_handle_stat(&dfd, &filename, &flag);\
#endif\
' fs/stat.c

;;

# ------------------------------------------------
# reboot.c
# ------------------------------------------------
kernel/reboot.c)

echo "[*] patching kernel/reboot.c"

sed -i '/SYSCALL_DEFINE4(reboot/i\
#ifdef CONFIG_KSU\
extern int ksu_handle_sys_reboot(int magic1, int magic2,\
        unsigned int cmd, void __user **arg);\
#endif\
' kernel/reboot.c

sed -i '/int ret = 0;/a\
#ifdef CONFIG_KSU\
    ksu_handle_sys_reboot(magic1, magic2, cmd, &arg);\
#endif\
' kernel/reboot.c

;;

esac

echo "[+] $i patched"
echo "--------------------------------"

done

echo "KernelSU manual patch finished"
