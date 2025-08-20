#!/bin/bash

# ==============================================================================
# Skrip Instalasi Ulang Pterodactyl Panel
# Dibuat untuk: Instalasi di Ubuntu dengan Nginx, MariaDB/MySQL, dan PHP 8.3
# ==============================================================================

# --- Variabel Konfigurasi ---
PANEL_DIR="/var/www/pterodactyl"
BACKUP_DIR="/root/pterodactyl_backups"
WEB_USER="www-data"

# --- Warna untuk Output ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --- Fungsi untuk Menampilkan Pesan ---
info() {
    echo -e "${YELLOW}[INFO] $1${NC}"
}

success() {
    echo -e "${GREEN}[SUKSES] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

# --- Memastikan Skrip Dijalankan sebagai Root ---
if [ "$EUID" -ne 0 ]; then
  error "Harap jalankan skrip ini sebagai root atau dengan sudo."
fi

# --- Peringatan dan Konfirmasi ---
echo -e "${RED}===================================================================${NC}"
echo -e "${RED}PERINGATAN!${NC}"
echo -e "${YELLOW}Skrip ini akan MENGHAPUS file panel Pterodactyl yang ada di ${PANEL_DIR} dan MENGHAPUS DATABASE-nya.${NC}"
echo -e "${YELLOW}Pastikan Anda mengerti apa yang Anda lakukan.${NC}"
echo -e "${YELLOW}File konfigurasi penting seperti '.env' akan di-backup ke ${BACKUP_DIR}.${NC}"
echo -e "${RED}===================================================================${NC}"
read -p "Apakah Anda yakin ingin melanjutkan? (y/n): " confirmation
if [[ "$confirmation" != "y" && "$confirmation" != "Y" ]]; then
    info "Instalasi ulang dibatalkan."
    exit 0
fi

# --- Meminta Password Root MySQL/MariaDB ---
read -s -p "Masukkan password root MySQL/MariaDB Anda: " MYSQL_ROOT_PASSWORD
echo "" # Baris baru setelah input password

# --- Langkah 1: Backup Konfigurasi Penting ---
info "Memulai proses backup..."
mkdir -p "$BACKUP_DIR"
if [ -f "$PANEL_DIR/.env" ]; then
    cp "$PANEL_DIR/.env" "$BACKUP_DIR/.env.bak.$(date +%F_%T)"
    success "File .env berhasil di-backup ke ${BACKUP_DIR}"
else
    error "File .env tidak ditemukan di ${PANEL_DIR}. Tidak ada yang bisa di-backup. Proses dibatalkan."
fi

# --- Langkah 2: Menghentikan Layanan Terkait ---
info "Menghentikan layanan Nginx, PHP-FPM, dan Pterodactyl..."
systemctl stop nginx
systemctl stop php8.3-fpm
systemctl stop pteroq
success "Layanan berhasil dihentikan."

# --- Langkah 3: Menghapus Database Lama dan Membuat yang Baru ---
info "Menghapus dan membuat ulang database Pterodactyl..."
DB_NAME=$(grep DB_DATABASE "$PANEL_DIR/.env" | cut -d '=' -f2)
DB_USER=$(grep DB_USERNAME "$PANEL_DIR/.env" | cut -d '=' -f2)
DB_PASSWORD=$(grep DB_PASSWORD "$PANEL_DIR/.env" | cut -d '=' -f2 | sed 's/"//g') # Menghilangkan kutip jika ada

if [ -z "$DB_NAME" ] || [ -z "$DB_USER" ] || [ -z "$DB_PASSWORD" ]; then
    error "Tidak dapat membaca detail database dari file .env. Proses dibatalkan."
fi

mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "DROP DATABASE IF EXISTS ${DB_NAME};"
mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "CREATE DATABASE ${DB_NAME};"
mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "FLUSH PRIVILEGES;"
success "Database '${DB_NAME}' telah dihapus dan dibuat ulang."

# --- Langkah 4: Menghapus File Panel Lama dan Mengunduh yang Baru ---
info "Menghapus file panel lama..."
rm -rf ${PANEL_DIR}/*
mkdir -p "$PANEL_DIR"
cd "$PANEL_DIR" || error "Gagal masuk ke direktori ${PANEL_DIR}."

info "Mengunduh file Pterodactyl Panel terbaru..."
curl -Lo panel.tar.gz "https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz"
tar -xzvf panel.tar.gz
rm -f panel.tar.gz
success "File panel terbaru berhasil diunduh dan diekstrak."

# --- Langkah 5: Konfigurasi Ulang Panel ---
info "Memulai konfigurasi ulang panel..."

info "Mengembalikan file .env dari backup..."
cp "$BACKUP_DIR/$(ls -t $BACKUP_DIR | grep .env.bak | head -1)" "$PANEL_DIR/.env"
success "File .env berhasil dikembalikan."

info "Menginstal dependensi Composer (ini mungkin butuh beberapa saat)..."
composer install --no-dev --optimize-autoloader

info "Menjalankan migrasi database dan seeding..."
php artisan migrate --seed --force

info "Membersihkan cache..."
php artisan view:clear
php artisan config:clear
php artisan cache:clear

info "Mengatur perizinan file..."
chown -R ${WEB_USER}:${WEB_USER} ${PANEL_DIR}/*
chmod -R 755 ${PANEL_DIR}/*

success "Konfigurasi ulang panel selesai."

# --- Langkah 6: Memulai Kembali Layanan ---
info "Memulai kembali layanan..."
systemctl start pteroq
systemctl start nginx
systemctl start php8.3-fpm
systemctl restart wings # Restart wings untuk memastikan koneksi baru ke panel
success "Semua layanan telah dimulai."

# --- Selesai ---
echo -e "\n${GREEN}===================================================================${NC}"
success "INSTALASI ULANG PTERODACTYL PANEL SELESAI!"
echo -e "${YELLOW}Silakan cek website panel Anda untuk memastikan semuanya berjalan normal.${NC}"
echo -e "${YELLOW}Jika Anda perlu membuat ulang akun admin, jalankan perintah berikut:${NC}"
echo -e "${YELLOW}cd ${PANEL_DIR} && php artisan p:user:make${NC}"
echo -e "${GREEN}===================================================================${NC}"
