#!/bin/bash
#
# KernelSU-Next Manual Patching Script (Refactored)
# Sesuai dengan dokumentasi resmi: https://kernelsu-next.github.io/webpage/pages/how-to-integrate-for-non-gki.html
#
# Author: Refactored based on KernelSU-Next official documentation
# Date: March 2025
# Kernel Support: 4.4 - 5.4 (Legacy mode for non-GKI devices)
#
# CATATAN PENTING:
# - Script ini hanya untuk patching manual jika kprobe tidak bekerja di kernel Anda
# - Jika kprobe bekerja, gunakan: curl -LSs "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/next/kernel/setup.sh" | bash -s legacy
# - Script harus dijalankan di root directory kernel source
#

set -e  # Exit on error

# ============================================================================
# KONFIGURASI
# ============================================================================

SCRIPT_VERSION="2.0"
PATCH_VERSION="1.9"
SCRIPT_NAME="KernelSU-Next Syscall Hook Patcher"
CORE_FILES=(
    "fs/exec.c"
    "fs/open.c"
    "fs/read_write.c"
    "fs/stat.c"
    "kernel/reboot.c"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# FUNGSI UTILITY
# ============================================================================

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}[✓] $1${NC}"
}

print_error() {
    echo -e "${RED}[✗] $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}[!] $1${NC}"
}

print_info() {
    echo -e "${BLUE}[i] $1${NC}"
}

# Ekstrak versi kernel dari Makefile
get_kernel_version() {
    if [[ ! -f "Makefile" ]]; then
        print_error "Makefile tidak ditemukan. Pastikan script dijalankan di root kernel source!"
        exit 1
    fi

    local version=$(grep -E "^VERSION = " Makefile | awk '{print $3}')
    local patchlevel=$(grep -E "^PATCHLEVEL = " Makefile | awk '{print $3}')
    local sublevel=$(grep -E "^SUBLEVEL = " Makefile | awk '{print $3}')

    if [[ -z "$version" ]] || [[ -z "$patchlevel" ]]; then
        print_error "Gagal mendapatkan versi kernel!"
        exit 1
    fi

    KERNEL_VERSION="${version}.${patchlevel}.${sublevel}"
    FIRST_VERSION=$version
    SECOND_VERSION=$patchlevel
}

# Validasi file yang akan di-patch
validate_files() {
    print_info "Memvalidasi file kernel source..."
    local missing_files=0

    for file in "${CORE_FILES[@]}"; do
        if [[ ! -f "$file" ]]; then
            print_warning "File $file tidak ditemukan"
            ((missing_files++))
        fi
    done

    if [[ $missing_files -gt 0 ]]; then
        print_error "$missing_files file tidak ditemukan!"
        return 1
    fi

    print_success "Semua file kernel ditemukan"
    return 0
}

# Cek apakah file sudah di-patch
check_if_patched() {
    local file=$1
    if grep -q "ksu_handle" "$file" 2>/dev/null; then
        return 0  # Already patched
    fi
    return 1  # Not patched
}

# ============================================================================
# FUNGSI PATCHING UTAMA
# ============================================================================

# Patch fs/exec.c
patch_exec_c() {
    local file="fs/exec.c"

    print_info "Memproses $file..."

    if check_if_patched "$file"; then
        print_warning "$file sudah mengandung KernelSU hooks, skip"
        return 0
    fi

    # Tambahkan deklarasi extern function sebelum do_execve
    sed -i '/^int do_execve(struct filename \*filename,/i\
#ifdef CONFIG_KSU\
__attribute__((hot))\
extern int ksu_handle_execveat(int *fd, struct filename **filename_ptr,\
\t\t\t\tvoid *argv, void *envp, int *flags);\
#endif\
' "$file"

    # Tambahkan call di do_execve
    sed -i '/struct user_arg_ptr argv = { .ptr.native = __argv };/a\
#ifdef CONFIG_KSU\
\tksu_handle_execveat((int *)AT_FDCWD, \&filename, \&argv, \&envp, 0);\
#endif' "$file"

    # Tambahkan call di compat_do_execve jika ada
    if grep -q "^static int compat_do_execve" "$file"; then
        sed -i '/\.ptr.compat = __envp,/a\
#ifdef CONFIG_KSU \/\/ 32-bit ksud and 32-on-64 support\
\tksu_handle_execveat((int *)AT_FDCWD, \&filename, \&argv, \&envp, 0);\
#endif' "$file"
    fi

    if grep -q "ksu_handle_execveat" "$file"; then
        print_success "$file patched!"
        grep -c "ksu_handle_execveat" "$file" | xargs -I {} echo "    Ditemukan {} hook(s)"
    else
        print_error "Patch $file gagal!"
        return 1
    fi
}

# Patch fs/open.c
patch_open_c() {
    local file="fs/open.c"

    print_info "Memproses $file..."

    if check_if_patched "$file"; then
        print_warning "$file sudah mengandung KernelSU hooks, skip"
        return 0
    fi

    # Tambahkan deklarasi extern function sebelum SYSCALL_DEFINE3(faccessat)
    sed -i '/^SYSCALL_DEFINE3(faccessat, int, dfd, const char __user \*, filename, int, mode)/i\
#ifdef CONFIG_KSU\
__attribute__((hot))\
extern int ksu_handle_faccessat(int *dfd, const char __user **filename_user,\
\t\t\t\tint *mode, int *flags);\
#endif\
' "$file"

    # Tambahkan call di awal SYSCALL_DEFINE3
    sed -i '/^SYSCALL_DEFINE3(faccessat, int, dfd, const char __user \*, filename, int, mode)/,/if (mode & ~S_IRWXO)/{
    /if (mode & ~S_IRWXO)/i\
#ifdef CONFIG_KSU\
\tksu_handle_faccessat(\&dfd, \&filename, \&mode, NULL);\
#endif\

}' "$file"

    if grep -q "ksu_handle_faccessat" "$file"; then
        print_success "$file patched!"
        grep -c "ksu_handle_faccessat" "$file" | xargs -I {} echo "    Ditemukan {} hook(s)"
    else
        print_error "Patch $file gagal!"
        return 1
    fi
}

# Patch fs/read_write.c
patch_read_write_c() {
    local file="fs/read_write.c"

    print_info "Memproses $file..."

    if check_if_patched "$file"; then
        print_warning "$file sudah mengandung KernelSU hooks, skip"
        return 0
    fi

    # Tambahkan deklarasi extern function sebelum SYSCALL_DEFINE3(read)
    sed -i '/^SYSCALL_DEFINE3(read, unsigned int, fd, char __user \*, buf, size_t, count)/i\
#ifdef CONFIG_KSU\
extern bool ksu_vfs_read_hook __read_mostly;\
extern __attribute__((cold)) int ksu_handle_sys_read(unsigned int fd,\
\t\t\t\tchar __user **buf_ptr, size_t *count_ptr);\
#endif\
' "$file"

    # Tambahkan call setelah fdget_pos
    sed -i '/struct fd f = fdget_pos(fd);/a\
#ifdef CONFIG_KSU\
\tif (unlikely(ksu_vfs_read_hook))\
\t\tksu_handle_sys_read(fd, \&buf, \&count);\
#endif' "$file"

    if grep -q "ksu_handle_sys_read" "$file"; then
        print_success "$file patched!"
        grep -c "ksu_handle_sys_read" "$file" | xargs -I {} echo "    Ditemukan {} hook(s)"
    else
        print_error "Patch $file gagal!"
        return 1
    fi
}

# Patch fs/stat.c
patch_stat_c() {
    local file="fs/stat.c"

    print_info "Memproses $file..."

    if check_if_patched "$file"; then
        print_warning "$file sudah mengandung KernelSU hooks, skip"
        return 0
    fi

    # Tambahkan deklarasi extern function
    sed -i '/#if !defined(__ARCH_WANT_STAT64) || defined(__ARCH_WANT_SYS_NEWFSTATAT)/i\
#ifdef CONFIG_KSU\
__attribute__((hot))\
extern int ksu_handle_stat(int *dfd, const char __user **filename_user,\
\t\t\t\tint *flags);\
#endif\
' "$file"

    # Tambahkan call di SYSCALL_DEFINE4(newfstatat)
    sed -i '/SYSCALL_DEFINE4(newfstatat, int, dfd, const char __user \*, filename,/,/int error;/{
    /int error;/a\
#ifdef CONFIG_KSU\
\tksu_handle_stat(\&dfd, \&filename, \&flag);\
#endif\

}' "$file"

    if grep -q "ksu_handle_stat" "$file"; then
        print_success "$file patched!"
        grep -c "ksu_handle_stat" "$file" | xargs -I {} echo "    Ditemukan {} hook(s)"
    else
        print_error "Patch $file gagal!"
        return 1
    fi
}

# Patch kernel/reboot.c
patch_reboot_c() {
    local file="kernel/reboot.c"

    print_info "Memproses $file..."

    if check_if_patched "$file"; then
        print_warning "$file sudah mengandung KernelSU hooks, skip"
        return 0
    fi

    # Tambahkan deklarasi extern function sebelum SYSCALL_DEFINE4(reboot)
    sed -i '/^SYSCALL_DEFINE4(reboot, int, magic1, int, magic2, unsigned int, cmd,/i\
#ifdef CONFIG_KSU\
extern int ksu_handle_sys_reboot(int magic1, int magic2, unsigned int cmd, void __user **arg);\
#endif\
' "$file"

    # Tambahkan call di awal SYSCALL_DEFINE4
    sed -i '/struct pid_namespace \*pid_ns = task_active_pid_ns(current);/a\
#ifdef CONFIG_KSU\
\tksu_handle_sys_reboot(magic1, magic2, cmd, \&arg);\
#endif' "$file"

    if grep -q "ksu_handle_sys_reboot" "$file"; then
        print_success "$file patched!"
        grep -c "ksu_handle_sys_reboot" "$file" | xargs -I {} echo "    Ditemukan {} hook(s)"
    else
        print_error "Patch $file gagal!"
        return 1
    fi
}

# ============================================================================
# FUNGSI VERIFIKASI DAN CLEANUP
# ============================================================================

verify_patches() {
    print_header "Verifikasi Hasil Patching"

    local all_patched=true

    for file in "${CORE_FILES[@]}"; do
        if [[ -f "$file" ]]; then
            if check_if_patched "$file"; then
                print_success "$file: Patched"
            else
                print_warning "$file: Not patched"
                all_patched=false
            fi
        fi
    done

    if $all_patched; then
        print_success "Semua file berhasil di-patch!"
        return 0
    else
        print_warning "Beberapa file belum di-patch"
        return 1
    fi
}

backup_files() {
    local backup_dir="kernel_backup_$(date +%Y%m%d_%H%M%S)"
    print_info "Membuat backup file kernel..."

    mkdir -p "$backup_dir"
    for file in "${CORE_FILES[@]}"; do
        if [[ -f "$file" ]]; then
            cp "$file" "$backup_dir/"
        fi
    done

    print_success "Backup dibuat di: $backup_dir"
}

# ============================================================================
# MAIN PROGRAM
# ============================================================================

main() {
    print_header "$SCRIPT_NAME v$SCRIPT_VERSION"
    echo "KernelSU-Next Patch Version: $PATCH_VERSION"
    echo "Script Type: Manual patching untuk non-GKI kernels"
    echo ""

    # Validasi environment
    print_info "Validasi environment..."
    get_kernel_version
    print_success "Kernel version: $KERNEL_VERSION"

    if ! validate_files; then
        print_error "Validasi file gagal!"
        exit 1
    fi

    echo ""

    # Buat backup
    read -p "Buat backup file sebelum patching? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        backup_files
        echo ""
    fi

    # Mulai patching
    print_header "Memulai Proses Patching"

    local failed_patches=0

    patch_exec_c || ((failed_patches++))
    echo ""

    patch_open_c || ((failed_patches++))
    echo ""

    patch_read_write_c || ((failed_patches++))
    echo ""

    patch_stat_c || ((failed_patches++))
    echo ""

    patch_reboot_c || ((failed_patches++))
    echo ""

    # Verifikasi
    verify_patches

    # Summary
    echo ""
    print_header "SUMMARY"
    if [[ $failed_patches -eq 0 ]]; then
        print_success "Patching selesai dengan sukses!"
        echo ""
        echo "Langkah selanjutnya:"
        echo "1. Pastikan CONFIG_KSU=y di defconfig:"
        echo "   grep CONFIG_KSU arch/arm64/configs/your_defconfig"
        echo ""
        echo "2. Build kernel:"
        echo "   make -j\$(nproc)"
        echo ""
        echo "3. Flash kernel ke device Anda"
        echo ""
        echo "Dokumentasi resmi: https://kernelsu-next.github.io/webpage/pages/how-to-integrate-for-non-gki.html"
    else
        print_error "$failed_patches patch(es) gagal. Cek output di atas!"
        exit 1
    fi
}

# Tampilkan help jika diperlukan
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  (none)     Jalankan patching"
    echo "  -h         Tampilkan help ini"
    echo "  --verify   Hanya verifikasi patches tanpa apply"
    echo ""
    echo "NOTES:"
    echo "- Script harus dijalankan di root directory kernel source"
    echo "- Backup file kernel source secara manual jika diperlukan"
    echo "- Untuk kprobe integration, gunakan setup.sh resmi:"
    echo "  curl -LSs \"https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/next/kernel/setup.sh\" | bash -s legacy"
    exit 0
fi

if [[ "$1" == "--verify" ]]; then
    get_kernel_version
    verify_patches
    exit 0
fi

# Eksekusi main
main
