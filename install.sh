#!/bin/bash

# ==============================================================================
# Skrip Install Bot WhatsApp Auto Reject - BLOKIR SEMENTARA 30 DETIK
# Fitur: Auto-Yes, Auto-Reboot, Offline Notif, Peringatan 3x, & Auto-Unblock 30s
# ==============================================================================

export DEBIAN_FRONTEND=noninteractive

clear
echo "=========================================================="
echo "       SETUP BOT WHATSAPP AUTO REJECT (CALL/VC)           "
echo "=========================================================="
echo "Memulai Proses Instalasi. Silakan duduk manis..."
echo "Sistem akan menginstal semuanya terlebih dahulu."
echo "=========================================================="

# 1. Update & Upgrade Sistem VPS
sudo apt-get update -y
sudo apt-get upgrade -y

# 2. Instal dependensi dasar
sudo apt-get install -y curl git build-essential tzdata

# 3. Instal Node.js (Versi LTS 20)
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# Update npm ke versi paling baru
sudo npm install -g npm@latest

# 4. Instal PM2 versi terbaru
sudo npm install -g pm2@latest

# 5. Membuat direktori kerja bot
BOT_DIR="$HOME/bot-autoreject"
mkdir -p $BOT_DIR
cd $BOT_DIR

# 6. Inisialisasi Project dan Instal dependensi bot
npm init -y
npm install @whiskeysockets/baileys@latest pino@latest
npm update 

# HAPUS SESI LAMA: Memastikan instalasi bersih
rm -rf auth_info_baileys

# 7. Membuat file utama bot (index.js)
cat << 'EOF' > index.js
const { default: makeWASocket, useMultiFileAuthState, DisconnectReason, Browsers, fetchLatestBaileysVersion } = require('@whiskeysockets/baileys');
const pino = require('pino');
const fs = require('fs');

process.on('uncaughtException', console.error);

// Set & Map untuk sistem Anti-Spam dan Auto-Block
const callCooldown = new Set();
const spamCount = new Map(); // Menyimpan jumlah panggilan dari setiap nomor

async function startBot() {
    const { state, saveCreds } = await useMultiFileAuthState('auth_info_baileys');
    const { version } = await fetchLatestBaileysVersion();

    const sock = makeWASocket({
        version,
        logger: pino({ level: 'silent' }),
        printQRInTerminal: false,
        auth: state,
        browser: Browsers.ubuntu('Chrome'),
        markOnlineOnConnect: false, 
        syncFullHistory: false
    });

    sock.ev.on('connection.update', async (update) => {
        const { connection, lastDisconnect, qr } = update;

        if (qr && !sock.authState.creds.registered) {
            setTimeout(async () => {
                try {
                    let phoneNumber = fs.readFileSync('wanumber.txt', 'utf8').trim();
                    phoneNumber = phoneNumber.replace(/[^0-9]/g, ''); 
                    const code = await sock.requestPairingCode(phoneNumber);
                    const formattedCode = code?.match(/.{1,4}/g)?.join('-') || code;
                    console.log(`\n======================================================`);
                    console.log(`📞 KODE PAIRING ANDA: ${formattedCode}`);
                    console.log(`Buka WA -> Perangkat Tertaut -> Tautkan dengan No. Telepon`);
                    console.log(`======================================================\n`);
                } catch (err) {
                    console.log('Gagal request kode pairing:', err.message);
                }
            }, 5000); 
        }

        if (connection === 'close') {
            const statusCode = lastDisconnect.error?.output?.statusCode;
            if (statusCode !== DisconnectReason.loggedOut) {
                setTimeout(() => startBot(), 5000);
            }
        } else if (connection === 'open') {
            console.log('✅ Bot Terhubung! Status disetel ke Offline agar notif HP bunyi.');
            await sock.sendPresenceUpdate('unavailable');
        }
    });

    sock.ev.on('creds.update', saveCreds);

    // AUTO REJECT CALL/VC DENGAN BLOKIR SEMENTARA 30 DETIK
    sock.ev.on('call', async (call) => {
        for (let c of call) {
            if (c.status === 'offer') {
                console.log(`❌ Menolak panggilan dari ${c.from}`);
                
                // 1. Langsung tolak panggilan detik itu juga
                await sock.rejectCall(c.id, c.from);
                
                // 2. Hitung jumlah panggilan masuk dari nomor ini
                let currentCount = spamCount.get(c.from) || 0;
                currentCount++;
                spamCount.set(c.from, currentCount);

                // Jika sudah menelpon 3 kali berturut-turut, otomatis di-Blokir Sementara
                if (currentCount >= 3) {
                    console.log(`🚨 BANNED: Memblokir nomor ${c.from} selama 30 DETIK karena Spam Call.`);
                    
                    // Kirim pesan terakhir sebelum diblokir (Menyebutkan 30 detik)
                    await sock.sendMessage(c.from, { 
                        text: '🛑 *Peringatan Sistem*\n\nAnda terdeteksi melakukan SPAM panggilan secara berulang. Sesuai peringatan, nomor Anda kini *DIBLOKIR SEMENTARA* selama 30 Detik.' 
                    });
                    
                    // Eksekusi pemblokiran nomor
                    await sock.updateBlockStatus(c.from, 'block');
                    
                    // Fitur Auto-Unblock setelah 30 Detik (30000 milidetik)
                    setTimeout(async () => {
                        try {
                            await sock.updateBlockStatus(c.from, 'unblock');
                            console.log(`🔓 UNBANNED: Nomor ${c.from} telah dibuka blokirnya.`);
                            
                            // Reset hitungan spam kembali ke nol setelah di-unblock
                            spamCount.delete(c.from);
                        } catch (err) {
                            console.log(`Gagal unblock nomor ${c.from}:`, err.message);
                        }
                    }, 30000);

                    continue; // Hentikan proses selanjutnya untuk nomor ini
                }
                
                // 3. Sistem Cooldown Pesan Peringatan Biasa (10 Detik)
                if (!callCooldown.has(c.from)) {
                    // Kirim pesan peringatan (Ditambahkan info akan diblokir jika 3x call)
                    await sock.sendMessage(c.from, { 
                        text: '🤖 *Pesan Otomatis*\n\nMohon maaf, saya sedang tidak bisa menerima panggilan (Call/VC). Silakan kirim pesan teks saja.\n\n⚠️ *Catatan:* Jika Anda melakukan panggilan hingga 3x berturut-turut, sistem akan memblokir nomor Anda secara otomatis.' 
                    });
                    
                    // Masukkan ke daftar cooldown
                    callCooldown.add(c.from);
                    
                    // Hapus dari cooldown pesan setelah 10 detik
                    setTimeout(() => {
                        callCooldown.delete(c.from);
                    }, 10000);
                }

                // 4. Pengurangan otomatis poin spam jika dia berhenti menelpon secara wajar (reset bertahap tiap 2 menit)
                setTimeout(() => {
                    let reduceCount = spamCount.get(c.from) || 0;
                    if (reduceCount > 0) {
                        spamCount.set(c.from, reduceCount - 1);
                    }
                }, 120000); 
            }
        }
    });

    sock.ev.on('messages.upsert', async m => {
        // Biarkan kosong agar pesan tetap unread dan notifikasi HP berbunyi
    });
}

startBot();
EOF

# ==============================================================================
# 8. PENGINSTALAN SELESAI, SEKARANG MINTA NOMOR WHATSAPP
# ==============================================================================
echo ""
echo "=========================================================="
echo " PENGINSTALAN SELESAI! SEKARANG SETUP NOMOR WHATSAPP ANDA "
echo "=========================================================="
echo "Silakan masukkan nomor WhatsApp yang akan digunakan."
read -p "Nomor WhatsApp: " WA_NUMBER </dev/tty

if [[ -z "$WA_NUMBER" ]]; then
   echo "Error: Nomor WhatsApp tidak boleh kosong!"
   exit 1
fi

echo "$WA_NUMBER" > wanumber.txt

# 9. Konfigurasi PM2 Auto-Restart
pm2 stop wa-autoreject 2>/dev/null
pm2 delete wa-autoreject 2>/dev/null
pm2 start index.js --name "wa-autoreject"
pm2 save

sudo env PATH=$PATH:$(dirname $(which node)) $(which pm2) startup systemd -u $(whoami) --hp $(eval echo ~$(whoami))
pm2 save

# 10. Selesai
echo "=========================================================="
echo "      BOT BERHASIL DIJALANKAN DI BACKGROUND               "
echo "=========================================================="
echo "Menunggu Kode Pairing muncul..."
sleep 4
pm2 logs wa-autoreject
