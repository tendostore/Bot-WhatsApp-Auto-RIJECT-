#!/bin/bash

HIJAU='\033[0;32m'
BIRU='\033[0;34m'
KUNING='\033[1;33m'
MERAH='\033[0;31m'
NORMAL='\033[0m'

clear
echo -e "${BIRU}==============================================${NORMAL}"
echo -e "${HIJAU}   AUTO-INSTALL WA BOT ANTI-CALL (ONE-CLICK)  ${NORMAL}"
echo -e "${BIRU}==============================================${NORMAL}"

echo -e "${KUNING}[*] Mengecek versi Node.js...${NORMAL}"
if command -v node &> /dev/null; then
    NODE_VER=$(node -v | cut -d 'v' -f 2 | cut -d '.' -f 1)
    echo -e "[*] Terdeteksi Node.js versi: $(node -v)"
else
    NODE_VER=0
fi

if [ "$NODE_VER" -lt 20 ]; then
    echo -e "${KUNING}[*] Membutuhkan Node.js v20+. Melakukan upgrade...${NORMAL}"
    if command -v apt &> /dev/null; then
        apt-get update && apt-get install -y curl
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
        apt-get install -y nodejs
    elif command -v pkg &> /dev/null; then
        pkg update -y && pkg install nodejs -y
    else
        echo -e "${MERAH}[!] OS tidak didukung otomatis. Update Node.js manual ke v20.${NORMAL}"
        exit 1
    fi
fi

echo -e "${KUNING}[*] Menyiapkan folder project...${NORMAL}"
rm -rf wa-bot-anticall
mkdir -p wa-bot-anticall
cd wa-bot-anticall

cat << 'EOF' > package.json
{
  "name": "wa-bot-anticall",
  "version": "1.0.0",
  "main": "index.js",
  "scripts": { "start": "node index.js" }
}
EOF

echo -e "${KUNING}[*] Menulis script utama (index.js)...${NORMAL}"
cat << 'EOF' > index.js
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
            const shouldReconnect = lastDisconnect.error?.output?.statusCode !== DisconnectReason.loggedOut;
            if (shouldReconnect) startBot();
        } else if (connection === 'open') {
            console.log('✅ Bot Berhasil Terhubung!');
        }
    });

    sock.ev.on('call', async (node) => {
        for (let call of node) {
            if (call.status === 'offer') {
                const callerId = call.from;
                
                // Membersihkan ID dari kode device (contoh: 62812..:1@s.whatsapp.net -> 62812..@s.whatsapp.net)
                const cleanJid = callerId.includes(':') ? callerId.split(':')[0] + '@s.whatsapp.net' : callerId;
                const cleanNumber = cleanJid.split('@')[0];

                try {
                    await sock.rejectCall(call.id, callerId);
                    
                    callCounts[cleanJid] = (callCounts[cleanJid] || 0) + 1;
                    const count = callCounts[cleanJid];

                    if (count === 1) {
                        await sock.sendMessage(cleanJid, { text: "⚠️ *PERINGATAN 1*\nMohon maaf, saya tidak menerima panggilan. Silakan chat saja." });
                    } else if (count === 2) {
                        await sock.sendMessage(cleanJid, { text: "⚠️ *PERINGATAN 2*\nJangan menelpon lagi atau nomor Anda akan diblokir otomatis oleh sistem." });
                    } else if (count >= 3) {
                        await sock.sendMessage(cleanJid, { text: "🚫 *DIBLOKIR SEMENTARA*\nNomor Anda diblokir selama 15 detik karena spam panggilan." });
                        
                        setTimeout(async () => {
                            try {
                                await sock.updateBlockStatus(cleanJid, 'block');
                                console.log(`[🚫] Memblokir ${cleanNumber}`);

                                setTimeout(async () => {
                                    try {
                                        await sock.updateBlockStatus(cleanJid, 'unblock');
                                        console.log(`[✅] Membuka blokir ${cleanNumber}`);
                                        delete callCounts[cleanJid];
                                    } catch (e) {
                                        console.log(`[!] Gagal unblock ${cleanNumber}:`, e.message);
                                    }
                                }, 15000);
                            } catch (e) {
                                console.log(`[!] Gagal block ${cleanNumber}:`, e.message);
                            }
                        }, 1000);
                    }
                } catch (e) {
                    console.log(`[!] Error memproses panggilan dari ${cleanNumber}:`, e.message);
                }
            }
        }
    });
}

startBot();
EOF

echo -e "${KUNING}[*] Menginstal library Baileys & Pino...${NORMAL}"
npm install @whiskeysockets/baileys pino

echo -e "${HIJAU}==============================================${NORMAL}"
echo -e "${HIJAU}      INSTALASI SELESAI! MENJALANKAN BOT...   ${NORMAL}"
echo -e "${HIJAU}==============================================${NORMAL}"
sleep 2
node index.js

