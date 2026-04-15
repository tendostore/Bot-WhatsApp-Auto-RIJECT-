#!/bin/bash
clear
echo "=========================================="
echo "  AUTO-INSTALL WA BOT ANTI-CALL PAIRING   "
echo "=========================================="
echo ""

# 1. Cek & Install Node.js otomatis
if ! command -v node &> /dev/null; then
    echo "[*] Node.js belum ada. Memulai instalasi..."
    if command -v pkg &> /dev/null; then
        pkg update -y && pkg upgrade -y
        pkg install nodejs -y
    elif command -v apt &> /dev/null; then
        sudo apt update && sudo apt install nodejs npm -y
    else
        echo "[!] OS tidak didukung untuk instalasi Node.js otomatis."
        exit 1
    fi
fi

# 2. Membuat Folder Project
echo "[*] Menyiapkan folder bot..."
mkdir -p wa-bot-anticall
cd wa-bot-anticall

# 3. Membuat file package.json (Kosongan agar otomatis diisi versi terbaru)
echo "[*] Membuat konfigurasi package.json..."
cat << 'EOF' > package.json
{
  "name": "wa-bot-anticall",
  "main": "index.js"
}
EOF

# 4. Membuat file index.js otomatis
echo "[*] Menulis script utama bot..."
cat << 'EOF' > index.js
// --- FIX UNTUK ERROR CRYPTO DI NODE.JS v18 ---
const crypto = require('crypto');
if (!global.crypto) global.crypto = crypto.webcrypto;
// ---------------------------------------------

const { default: makeWASocket, useMultiFileAuthState, DisconnectReason, fetchLatestBaileysVersion, makeCacheableSignalKeyStore } = require('@whiskeysockets/baileys');
const pino = require('pino');
const readline = require('readline');
const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
const question = (text) => new Promise((resolve) => rl.question(text, resolve));
const callCounts = {}; 

async function startBot() {
    const { state, saveCreds } = await useMultiFileAuthState('auth_info_baileys');
    const { version } = await fetchLatestBaileysVersion();
    const sock = makeWASocket({
        version,
        logger: pino({ level: 'silent' }),
        printQRInTerminal: false,
        auth: { creds: state.creds, keys: makeCacheableSignalKeyStore(state.keys, pino({ level: 'silent' })) },
        browser: ["Ubuntu", "Chrome", "20.0.04"]
    });

    if (!sock.authState.creds.registered) {
        console.clear();
        console.log("========================================");
        console.log("   WHATSAPP BOT ANTI-CALL PAIRING");
        console.log("========================================\n");
        const phoneNumber = await question('Masukkan nomor WA (Contoh: 62812xxx): ');
        const code = await sock.requestPairingCode(phoneNumber.replace(/[^0-9]/g, ''));
        console.log(`\n> KODE PAIRING ANDA: ${code} <\n`);
    }
    
    sock.ev.on('creds.update', saveCreds);
    sock.ev.on('connection.update', (update) => {
        const { connection, lastDisconnect } = update;
        if (connection === 'close') {
            if (lastDisconnect.error?.output?.statusCode !== DisconnectReason.loggedOut) startBot();
        } else if (connection === 'open') {
            console.log('✅ Bot Berhasil Terhubung!');
        }
    });

    sock.ev.on('call', async (node) => {
        for (let call of node) {
            if (call.status === 'offer') {
                const callerId = call.from;
                
                await sock.rejectCall(call.id, callerId);
                console.log(`[!] Panggilan ditolak dari ${callerId.split('@')[0]}`);
                
                callCounts[callerId] = (callCounts[callerId] || 0) + 1;
                const count = callCounts[callerId];

                if (count === 1) {
                    console.log(`[⚠️] Peringatan 1 dikirim ke ${callerId.split('@')[0]}`);
                    await sock.sendMessage(callerId, { text: "⚠️ *PERINGATAN 1*\nMaaf, sistem kami tidak menerima panggilan telepon. Mohon kirimkan pesan teks saja." });
                
                } else if (count === 2) {
                    console.log(`[⚠️] Peringatan 2 dikirim ke ${callerId.split('@')[0]}`);
                    await sock.sendMessage(callerId, { text: "⚠️ *PERINGATAN 2*\nTolong jangan menelpon lagi. Jika Anda menelpon sekali lagi, nomor Anda akan diblokir otomatis oleh sistem." });
                
                } else if (count >= 3) {
                    console.log(`[🚫] Memblokir ${callerId.split('@')[0]} (3x spam telepon)...`);
                    
                    await sock.sendMessage(callerId, { text: "🚫 *DIBLOKIR SEMENTARA*\nAnda terdeteksi melakukan spam panggilan. Nomor Anda diblokir selama 15 detik." });
                    
                    setTimeout(async () => {
                        await sock.updateBlockStatus(callerId, 'block');
                        
                        setTimeout(async () => {
                            console.log(`[✅] Membuka blokir ${callerId.split('@')[0]} setelah 15 detik...`);
                            await sock.updateBlockStatus(callerId, 'unblock');
                            delete callCounts[callerId];
                        }, 15000);
                    }, 1000);
                }
            }
        }
    });
}
startBot();
EOF

# 5. Proses Instalasi Library (OTOMATIS VERSI TERBARU)
echo "[*] Menginstal library Baileys & Pino versi terbaru (Mohon tunggu sebentar)..."
npm install @whiskeysockets/baileys pino > /dev/null 2>&1

# 6. Menjalankan Bot
echo "[*] Instalasi selesai! Memulai bot..."
node index.js

