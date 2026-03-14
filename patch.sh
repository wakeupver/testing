#!/bin/bash

# Patches author: backslashxx @ Github
# Modified for kernel 4.9 compatibility (POCO F1 / SDM845)
# Shell author: JackA1ltman
# Compatible kernel: 3.18 – 5.4 (focus 4.9)

PATCH_LEVEL="2.0"

patch_files=(
fs/exec.c
fs/open.c
fs/read_write.c
fs/stat.c
kernel/reboot.c
)

KERNEL_VERSION=$(head -n 3 Makefile | grep -E 'VERSION|PATCHLEVEL' | awk '{print $3}' | paste -sd '.')
FIRST_VERSION=$(echo "$KERNEL_VERSION" | awk -F '.' '{print $1}')
SECOND_VERSION=$(echo "$KERNEL_VERSION" | awk -F '.' '{print $2}')

echo "Kernel Version: $KERNEL_VERSION"
echo "KernelSU Patch Version: $PATCH_LEVEL"

echo "=============================="

for i in "${patch_files[@]}"; do

if [ ! -f "$i" ]; then
echo "[-] Skip $i (file not found)"
continue
fi

if grep -q "ksu_handle" "$i"; then
echo "[-] $i already patched"
continue
fi

case $i in

################################
# exec.c
################################
fs/exec.c)

echo "[*] Patching fs/exec.c"

sed -i '/static int do_execveat_common(/i\
#ifdef CONFIG_KSU\
extern bool ksu_execveat_hook __read_mostly;\
extern int ksu_handle_execveat(int *fd, struct filename **filename_ptr, void *argv, void *envp, int *flags);\
extern int ksu_handle_execveat_sucompat(int *fd, struct filename **filename_ptr, void *argv, void *envp, int *flags);\
#endif\
' fs/exec.c

sed -i '/if (IS_ERR(filename))/i\
#ifdef CONFIG_KSU\
if (unlikely(ksu_execveat_hook))\
    ksu_handle_execveat(&fd, &filename, &argv, &envp, &flags);\
else\
    ksu_handle_execveat_sucompat(&fd, &filename, &argv, &envp, &flags);\
#endif\
' fs/exec.c

echo "[+] fs/exec.c patched"

;;

################################
# open.c
################################
fs/open.c)

echo "[*] Patching fs/open.c"

sed -i '/SYSCALL_DEFINE3(faccessat/i\
#ifdef CONFIG_KSU\
extern int ksu_handle_faccessat(int *dfd, const char __user **filename_user, int *mode, int *flags);\
#endif\
' fs/open.c

if grep -q "return do_faccessat" fs/open.c; then

sed -i '/return do_faccessat/i\
#ifdef CONFIG_KSU\
ksu_handle_faccessat(&dfd, &filename, &mode, NULL);\
#endif\
' fs/open.c

else

sed -i '/if (mode & ~S_IRWXO)/i\
#ifdef CONFIG_KSU\
ksu_handle_faccessat(&dfd, &filename, &mode, NULL);\
#endif\
' fs/open.c

fi

echo "[+] fs/open.c patched"

;;

################################
# read_write.c
################################
fs/read_write.c)

echo "[*] Patching fs/read_write.c"

sed -i '/SYSCALL_DEFINE3(read/i\
#ifdef CONFIG_KSU\
extern bool ksu_vfs_read_hook __read_mostly;\
extern int ksu_handle_sys_read(unsigned int fd, char __user **buf_ptr, size_t *count_ptr);\
#endif\
' fs/read_write.c

if grep -q "return ksys_read(fd, buf, count);" fs/read_write.c; then

sed -i '/return ksys_read(fd, buf, count);/i\
#ifdef CONFIG_KSU\
if (unlikely(ksu_vfs_read_hook))\
    ksu_handle_sys_read(fd, &buf, &count);\
#endif\
' fs/read_write.c

else

sed -i '0,/if (f.file)/s//\
#ifdef CONFIG_KSU\
if (unlikely(ksu_vfs_read_hook))\
    ksu_handle_sys_read(fd, &buf, &count);\
#endif\
if (f.file)/' fs/read_write.c

fi

echo "[+] fs/read_write.c patched"

;;

################################
# stat.c
################################
fs/stat.c)

echo "[*] Patching fs/stat.c"

sed -i '/#if !defined(__ARCH_WANT_STAT64)/i\
#ifdef CONFIG_KSU\
extern int ksu_handle_stat(int *dfd, const char __user **filename_user, int *flags);\
#endif\
' fs/stat.c

if grep -q "vfs_fstatat" fs/stat.c; then

sed -i '/vfs_fstatat/i\
#ifdef CONFIG_KSU\
ksu_handle_stat(&dfd, &filename, &flag);\
#endif\
' fs/stat.c

fi

echo "[+] fs/stat.c patched"

;;

################################
# reboot.c
################################
kernel/reboot.c)

echo "[*] Patching kernel/reboot.c"

sed -i '/SYSCALL_DEFINE4(reboot/i\
#ifdef CONFIG_KSU\
extern int ksu_handle_sys_reboot(int magic1, int magic2, unsigned int cmd, void __user **arg);\
#endif\
' kernel/reboot.c

sed -i '/int ret = 0;/a\
#ifdef CONFIG_KSU\
ksu_handle_sys_reboot(magic1, magic2, cmd, &arg);\
#endif\
' kernel/reboot.c

echo "[+] kernel/reboot.c patched"

;;

esac

echo "------------------------------"

done

echo ""
echo "KernelSU manual integration patch finished."
echo ""
