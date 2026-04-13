#!/bin/bash

# ==============================================================================
# Skrip Install Bot WhatsApp Auto Reject - FIX FATAL BLOKIR (DOUBLE DEFENSE)
# Fitur: Auto-Yes, CS Ramah, Normalisasi JID, & Local Blacklist 15 Detik
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
const { default: makeWASocket, useMultiFileAuthState, DisconnectReason, Browsers, fetchLatestBaileysVersion, jidNormalizedUser } = require('@whiskeysockets/baileys');
const pino = require('pino');
const fs = require('fs');

process.on('uncaughtException', console.error);

// Map & Set untuk sistem Anti-Spam dan Blacklist Lokal
const spamCount = new Map();
const localBlacklist = new Set();

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
            console.log('\n✅ BERHASIL! Bot sudah Terhubung ke WhatsApp Anda.');
            console.log('Status WhatsApp disetel ke Offline agar notifikasi HP tetap bunyi.\n');
            await sock.sendPresenceUpdate('unavailable');
        }
    });

    sock.ev.on('creds.update', saveCreds);

    // LOGIKA AUTO REJECT & BLOCK BERTAHAP
    sock.ev.on('call', async (call) => {
        for (let c of call) {
            if (c.status === 'offer') {
                const callerId = c.from; 
                
                // MENGGUNAKAN FUNGSI RESMI BAILEYS UNTUK MENDAPATKAN ID ASLI YANG VALID
                const cleanJid = jidNormalizedUser(callerId);
                
                // PERTAHANAN LAPIS 1: Cek apakah nomor ini sedang dalam status Blacklist 15 Detik
                if (localBlacklist.has(cleanJid)) {
                    // Bunuh panggilan seketika tanpa perlu mengirim chat atau print log panjang
                    await sock.rejectCall(c.id, callerId);
                    console.log(`[SHIELD] Meredam panggilan dari nomor terblokir: ${cleanJid}`);
                    continue;
                }

                console.log(`\n[CALL] Panggilan masuk dari: ${cleanJid}`);
                
                // Tolak panggilan instan untuk proses reguler
                await sock.rejectCall(c.id, callerId);
                
                // Update hitungan spam
                let count = (spamCount.get(cleanJid) || 0) + 1;
                spamCount.set(cleanJid, count);
                
                console.log(`[STATUS] Akumulasi panggilan nomor ini: ${count}/3`);

                if (count === 1) {
                    await sock.sendMessage(cleanJid, { 
                        text: 'Halo kak! 🙏\n\nMohon maaf sekali, saat ini kami hanya melayani via pesan teks (chat) agar semua pertanyaan bisa terlayani dengan baik. \n\nSilakan ketikkan pesan kakak di sini ya. Terima kasih! 🛒✨' 
                    });
                } 
                else if (count === 2) {
                    await sock.sendMessage(cleanJid, { 
                        text: '🤖 *Info Sistem Bot*\n\nMohon pengertiannya ya kak 🙏, sistem mendeteksi panggilan berulang. Silakan gunakan pesan teks saja agar sistem tidak error.\n\nJika panggilan dilanjutkan (ke-3), sistem akan memblokir nomor kakak sementara.' 
                    });
                } 
                else if (count === 3) {
                    console.log(`[ACTION] Mengaktifkan pemblokiran untuk ${cleanJid} selama 15 detik...`);
                    
                    // Masukkan ke Blacklist Lokal (Pertahanan Lapis 1 aktif!)
                    localBlacklist.add(cleanJid);

                    await sock.sendMessage(cleanJid, { 
                        text: '🤖 *Sistem Auto-Block*\n\nMohon maaf kak, nomor ini telah diblokir sementara selama 15 detik karena panggilan beruntun. \n\nSilakan tinggalkan pesan teks setelah blokir terbuka ya kak. Terima kasih 🙏' 
                    });
                    
                    // JEDA 2 DETIK: Memastikan status telepon di server WA benar-benar mati sebelum diblokir
                    setTimeout(async () => {
                        try {
                            // Pertahanan Lapis 2: Blokir dari Server WA
                            await sock.updateBlockStatus(cleanJid, 'block');
                            console.log(`[BERHASIL] Server WA memblokir: ${cleanJid}`);
                        } catch (err) {
                            console.log(`[GAGAL BLOKIR SERVER] Error: ${err.message} (Namun Blacklist Lokal tetap aktif!)`);
                        }
                    }, 2000);

                    // Buka Blokir setelah 15 detik
                    setTimeout(async () => {
                        try {
                            await sock.updateBlockStatus(cleanJid, 'unblock');
                            console.log(`[ACTION] Blokir server dibuka untuk: ${cleanJid}`);
                        } catch (err) {
                            console.log(`[GAGAL UNBLOCK SERVER] Error: ${err.message}`);
                        } finally {
                            // Selalu pastikan Blacklist Lokal dan hitungan spam di-reset
                            localBlacklist.delete(cleanJid);
                            spamCount.delete(cleanJid);
                            console.log(`[ACTION] Blacklist Lokal dibersihkan untuk: ${cleanJid}`);
                        }
                    }, 15000);
                }

                // Reset hitungan peringatan otomatis jika tidak ada panggilan lagi dalam 5 menit
                setTimeout(() => {
                    if (spamCount.has(cleanJid) && spamCount.get(cleanJid) < 3) {
                        spamCount.delete(cleanJid);
                    }
                }, 300000);
            }
        }
    });

    sock.ev.on('messages.upsert', async m => {
        // Biarkan kosong agar notifikasi HP tetap prioritas
    });
}

startBot();
EOF

# ==============================================================================
# 8. INPUT NOMOR & SETUP PM2
# ==============================================================================
echo ""
echo "=========================================================="
echo " PENGINSTALAN SELESAI! SEKARANG SETUP NOMOR WHATSAPP ANDA "
echo "=========================================================="
read -p "Nomor WhatsApp (Contoh: 628123xxx): " WA_NUMBER </dev/tty

if [[ -z "$WA_NUMBER" ]]; then
   echo "Error: Nomor tidak boleh kosong!"
   exit 1
fi

echo "$WA_NUMBER" > wanumber.txt

# Pembersihan proses lama sebelum menjalankan yang baru
pm2 stop wa-autoreject 2>/dev/null
pm2 delete wa-autoreject 2>/dev/null
pm2 start index.js --name "wa-autoreject"
pm2 save

sudo env PATH=$PATH:$(dirname $(which node)) $(which pm2) startup systemd -u $(whoami) --hp $(eval echo ~$(whoami))
pm2 save

# 9. Tampilan Akhir & Log
clear
echo "=========================================================="
echo "      BOT BERHASIL DIJALANKAN DI BACKGROUND               "
echo "=========================================================="
echo "1. Buka WhatsApp -> Perangkat Tertaut."
echo "2. Pilih 'Tautkan dengan nomor telepon saja'."
echo "3. Masukkan kode pairing di bawah ini."
echo "=========================================================="
sleep 2
tail -f ~/.pm2/logs/wa-autoreject-out.log
