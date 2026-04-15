#!/bin/bash

# Warna untuk tampilan terminal
HIJAU='\033[0;32m'
BIRU='\033[0;34m'
KUNING='\033[1;33m'
NORMAL='\033[0m'

clear
echo -e "${BIRU}==============================================${NORMAL}"
echo -e "${HIJAU}   AUTO-INSTALL WA BOT ANTI-CALL (ONE-CLICK)  ${NORMAL}"
echo -e "${BIRU}==============================================${NORMAL}"

# 1. Cek & Install Node.js
if ! command -v node &> /dev/null; then
    echo -e "${KUNING}[*] Node.js belum ada. Menginstal Node.js...${NORMAL}"
    if command -v pkg &> /dev/null; then
        pkg update -y && pkg install nodejs -y
    elif command -v apt &> /dev/null; then
        sudo apt update && sudo apt install nodejs npm -y
    else
        echo -e "\033[0;31m[!] OS tidak didukung otomatis. Install Node.js manual.\033[0m"
        exit 1
    fi
fi

# 2. Membuat Folder Project
echo -e "${KUNING}[*] Menyiapkan folder project...${NORMAL}"
mkdir -p wa-bot-anticall
cd wa-bot-anticall

# 3. Membuat file package.json
cat << 'EOF' > package.json
{
  "name": "wa-bot-anticall",
  "version": "1.0.0",
  "description": "WhatsApp Bot Anti-Call by Gemini",
  "main": "index.js",
  "scripts": {
    "start": "node index.js"
  }
}
EOF

# 4. Membuat file index.js (Script Utama)
echo -e "${KUNING}[*] Menulis script utama (index.js)...${NORMAL}"
cat << 'EOF' > index.js
// Fix untuk Node.js v18 (Error Crypto)
const crypto = require('crypto');
if (!global.crypto) global.crypto = crypto.webcrypto;

const { 
    default: makeWASocket, 
    useMultiFileAuthState, 
    DisconnectReason, 
    fetchLatestBaileysVersion, 
    makeCacheableSignalKeyStore 
} = require('@whiskeysockets/baileys');
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
        auth: {
            creds: state.creds,
            keys: makeCacheableSignalKeyStore(state.keys, pino({ level: 'silent' })),
        },
        browser: ["Ubuntu", "Chrome", "20.0.04"]
    });

    // Fitur Pairing Code
    if (!sock.authState.creds.registered) {
        console.clear();
        console.log("========================================");
        console.log("   WHATSAPP BOT ANTI-CALL PAIRING");
        console.log("========================================\n");
        const phoneNumber = await question('Masukkan nomor WhatsApp (Contoh: 62812xxx): ');
        const code = await sock.requestPairingCode(phoneNumber.replace(/[^0-9]/g, ''));
        console.log(`\n> KODE PAIRING ANDA: ${code} <\n`);
    }

    sock.ev.on('creds.update', saveCreds);

    sock.ev.on('connection.update', (update) => {
        const { connection, lastDisconnect } = update;
        if (connection === 'close') {
            const shouldReconnect = lastDisconnect.error?.output?.statusCode !== DisconnectReason.loggedOut;
            if (shouldReconnect) startBot();
        } else if (connection === 'open') {
            console.log('✅ Bot Berhasil Terhubung!');
        }
    });

    // Logika Anti-Call
    sock.ev.on('call', async (node) => {
        for (let call of node) {
            if (call.status === 'offer') {
                const callerId = call.from;
                await sock.rejectCall(call.id, callerId);
                
                callCounts[callerId] = (callCounts[callerId] || 0) + 1;
                const count = callCounts[callerId];

                if (count === 1) {
                    await sock.sendMessage(callerId, { text: "⚠️ *PERINGATAN 1*\nMohon maaf, saya tidak menerima panggilan. Silakan chat saja." });
                } else if (count === 2) {
                    await sock.sendMessage(callerId, { text: "⚠️ *PERINGATAN 2*\nJangan menelpon lagi atau nomor Anda akan diblokir otomatis oleh sistem." });
                } else if (count >= 3) {
                    await sock.sendMessage(callerId, { text: "🚫 *DIBLOKIR SEMENTARA*\nNomor Anda diblokir selama 15 detik karena spam panggilan." });
                    
                    setTimeout(async () => {
                        await sock.updateBlockStatus(callerId, 'block');
                        console.log(`[🚫] Memblokir ${callerId.split('@')[0]}`);

                        setTimeout(async () => {
                            await sock.updateBlockStatus(callerId, 'unblock');
                            console.log(`[✅] Membuka blokir ${callerId.split('@')[0]}`);
                            delete callCounts[callerId];
                        }, 15000); // 15 detik
                    }, 1000);
                }
            }
        }
    });
}

startBot();
EOF

# 5. Instalasi Modul (Terlihat Log-nya)
echo -e "${KUNING}[*] Menginstal library terbaru (Baileys & Pino)...${NORMAL}"
npm install @whiskeysockets/baileys pino

# 6. Selesai
echo -e "${HIJAU}==============================================${NORMAL}"
echo -e "${HIJAU}      INSTALASI SELESAI! MENJALANKAN BOT...   ${NORMAL}"
echo -e "${HIJAU}==============================================${NORMAL}"
sleep 2
node index.js

