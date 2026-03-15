#!/bin/bash
# KernelSU-Next Kernel Source Patches
# Official Reference: https://kernelsu-next.github.io/webpage/pages/how-to-integrate-for-non-gki.html
# Patches for non-GKI kernel integration
# Compatible with kernel versions: 4.4, 4.9, 4.14, 4.19, 5.4 and later

set -e

PATCH_VERSION="1.0-next"
COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_NC='\033[0m'

# Function to print colored output
print_info() {
    echo -e "${COLOR_GREEN}[+]${COLOR_NC} $1"
}

print_error() {
    echo -e "${COLOR_RED}[-]${COLOR_NC} $1"
}

print_warning() {
    echo -e "${COLOR_YELLOW}[!]${COLOR_NC} $1"
}

print_section() {
    echo "======================================"
    echo "$1"
    echo "======================================"
}

# Check if files exist
check_file_exists() {
    if [ ! -f "$1" ]; then
        print_error "File not found: $1"
        return 1
    fi
    return 0
}

# Check if patch already applied
is_patched() {
    if grep -q "ksu_handle" "$1" 2>/dev/null; then
        return 0
    fi
    return 1
}

echo ""
print_section "KernelSU-Next Kernel Source Patcher v${PATCH_VERSION}"
echo ""

# Patch fs/exec.c
if check_file_exists "fs/exec.c"; then
    print_section "Patching fs/exec.c"
    
    if is_patched "fs/exec.c"; then
        print_warning "fs/exec.c already contains KernelSU patches"
        echo ""
    else
        print_info "Applying patches to fs/exec.c..."
        
        # Add extern declaration before do_execve function
        sed -i '/^int do_execve(struct filename \*filename,/i\
#ifdef CONFIG_KSU\
__attribute__((hot))\
extern int ksu_handle_execveat(int *fd, struct filename **filename_ptr,\
\t\t\t\tvoid *argv, void *envp, int *flags);\
#endif\
' fs/exec.c
        
        # Add ksu_handle_execveat call in do_execve (first occurrence)
        sed -i '0,/return do_execveat_common(AT_FDCWD, filename, argv, envp, 0);/{
            s/return do_execveat_common(AT_FDCWD, filename, argv, envp, 0);/#ifdef CONFIG_KSU\
\tksu_handle_execveat((int *)AT_FDCWD, \&filename, \&argv, \&envp, 0);\
#endif\
\treturn do_execveat_common(AT_FDCWD, filename, argv, envp, 0);/
        }' fs/exec.c
        
        # Add ksu_handle_execveat call in compat_do_execve (second occurrence - 32-bit support)
        awk '
        /return do_execveat_common\(AT_FDCWD, filename, argv, envp, 0\);/ {
            count++
            if (count == 2) {
                print "#ifdef CONFIG_KSU // 32-bit ksud and 32-on-64 support"
                print "\tksu_handle_execveat((int *)AT_FDCWD, &filename, &argv, &envp, 0);"
                print "#endif"
            }
        }
        { print }
        ' fs/exec.c > fs/exec.c.tmp && mv fs/exec.c.tmp fs/exec.c
        
        if grep -q "ksu_handle_execveat" "fs/exec.c"; then
            print_info "fs/exec.c successfully patched!"
            print_info "Total ksu_handle_execveat calls: $(grep -c "ksu_handle_execveat" "fs/exec.c")"
        else
            print_error "fs/exec.c patch failed!"
            exit 1
        fi
    fi
    echo ""
fi

# Patch fs/open.c
if check_file_exists "fs/open.c"; then
    print_section "Patching fs/open.c"
    
    if is_patched "fs/open.c"; then
        print_warning "fs/open.c already contains KernelSU patches"
        echo ""
    else
        print_info "Applying patches to fs/open.c..."
        
        # Add extern declaration before SYSCALL_DEFINE3(faccessat)
        sed -i '/^SYSCALL_DEFINE3(faccessat, int, dfd, const char __user \*, filename, int, mode)/i\
#ifdef CONFIG_KSU\
__attribute__((hot))\
extern int ksu_handle_faccessat(int *dfd, const char __user **filename_user,\
\t\t\t\tint *mode, int *flags);\
#endif\
' fs/open.c
        
        # Add ksu_handle_faccessat call before mode check
        sed -i '/if (mode & ~S_IRWXO)/i\
#ifdef CONFIG_KSU\
\tksu_handle_faccessat(\&dfd, \&filename, \&mode, NULL);\
#endif\
' fs/open.c
        
        if grep -q "ksu_handle_faccessat" "fs/open.c"; then
            print_info "fs/open.c successfully patched!"
            print_info "Total ksu_handle_faccessat calls: $(grep -c "ksu_handle_faccessat" "fs/open.c")"
        else
            print_error "fs/open.c patch failed!"
            exit 1
        fi
    fi
    echo ""
fi

# Patch fs/read_write.c
if check_file_exists "fs/read_write.c"; then
    print_section "Patching fs/read_write.c"
    
    if is_patched "fs/read_write.c"; then
        print_warning "fs/read_write.c already contains KernelSU patches"
        echo ""
    else
        print_info "Applying patches to fs/read_write.c..."
        
        # Add extern declarations before SYSCALL_DEFINE3(read)
        sed -i '/^SYSCALL_DEFINE3(read, unsigned int, fd, char __user \*, buf, size_t, count)/i\
#ifdef CONFIG_KSU\
extern bool ksu_vfs_read_hook __read_mostly;\
extern __attribute__((cold)) int ksu_handle_sys_read(unsigned int fd,\
\t\t\tchar __user **buf_ptr, size_t *count_ptr);\
#endif\
' fs/read_write.c
        
        # Add ksu_handle_sys_read call after fdget_pos (before if (f.file))
        sed -i '/if (f.file) {/i\
#ifdef CONFIG_KSU\
\tif (unlikely(ksu_vfs_read_hook))\
\t\tksu_handle_sys_read(fd, \&buf, \&count);\
#endif\
' fs/read_write.c
        
        if grep -q "ksu_handle_sys_read" "fs/read_write.c"; then
            print_info "fs/read_write.c successfully patched!"
            print_info "Total ksu_handle_sys_read calls: $(grep -c "ksu_handle_sys_read" "fs/read_write.c")"
        else
            print_error "fs/read_write.c patch failed!"
            exit 1
        fi
    fi
    echo ""
fi

# Patch fs/stat.c
if check_file_exists "fs/stat.c"; then
    print_section "Patching fs/stat.c"
    
    if is_patched "fs/stat.c"; then
        print_warning "fs/stat.c already contains KernelSU patches"
        echo ""
    else
        print_info "Applying patches to fs/stat.c..."
        
        # Add extern declaration before #if !defined(__ARCH_WANT_STAT64)
        sed -i '/#if !defined(__ARCH_WANT_STAT64) || defined(__ARCH_WANT_SYS_NEWFSTATAT)/i\
#ifdef CONFIG_KSU\
__attribute__((hot))\
extern int ksu_handle_stat(int *dfd, const char __user **filename_user,\
\t\t\t\tint *flags);\
#endif\
' fs/stat.c
        
        # Add ksu_handle_stat call before vfs_fstatat
        sed -i '/error = vfs_fstatat(dfd, filename, &stat, flag);/i\
#ifdef CONFIG_KSU\
\tksu_handle_stat(\&dfd, \&filename, \&flag);\
#endif\
' fs/stat.c
        
        if grep -q "ksu_handle_stat" "fs/stat.c"; then
            print_info "fs/stat.c successfully patched!"
            print_info "Total ksu_handle_stat calls: $(grep -c "ksu_handle_stat" "fs/stat.c")"
        else
            print_error "fs/stat.c patch failed!"
            exit 1
        fi
    fi
    echo ""
fi

# Patch kernel/reboot.c
if check_file_exists "kernel/reboot.c"; then
    print_section "Patching kernel/reboot.c"
    
    if is_patched "kernel/reboot.c"; then
        print_warning "kernel/reboot.c already contains KernelSU patches"
        echo ""
    else
        print_info "Applying patches to kernel/reboot.c..."
        
        # Add extern declaration before SYSCALL_DEFINE4(reboot)
        sed -i '/^SYSCALL_DEFINE4(reboot, int, magic1, int, magic2, unsigned int, cmd,/i\
#ifdef CONFIG_KSU\
extern int ksu_handle_sys_reboot(int magic1, int magic2, unsigned int cmd, void __user **arg);\
#endif\
' kernel/reboot.c
        
        # Add ksu_handle_sys_reboot call after "int ret = 0;"
        sed -i '/int ret = 0;/a\
#ifdef CONFIG_KSU\
\tksu_handle_sys_reboot(magic1, magic2, cmd, \&arg);\
#endif\
' kernel/reboot.c
        
        if grep -q "ksu_handle_sys_reboot" "kernel/reboot.c"; then
            print_info "kernel/reboot.c successfully patched!"
            print_info "Total ksu_handle_sys_reboot calls: $(grep -c "ksu_handle_sys_reboot" "kernel/reboot.c")"
        else
            print_error "kernel/reboot.c patch failed!"
            exit 1
        fi
    fi
    echo ""
fi

echo ""
print_section "Patching Complete"
print_info "All KernelSU-Next patches have been successfully applied!"
echo ""
print_info "Next steps:"
echo "1. Add CONFIG_KSU=y to your kernel defconfig"
echo "2. Build the kernel with KernelSU-Next integrated"
echo ""
print_info "Reference: https://kernelsu-next.github.io/webpage/pages/how-to-integrate-for-non-gki.html"
echo ""
