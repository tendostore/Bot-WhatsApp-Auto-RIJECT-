#!/bin/bash

HIJAU='\033[0;32m'
BIRU='\033[0;34m'
KUNING='\033[1;33m'
MERAH='\033[0;31m'
NORMAL='\033[0m'

clear
echo -e "${BIRU}==============================================${NORMAL}"
echo -e "${HIJAU}   AUTO-INSTALL WA BOT ANTI-CALL (SIMPLE)     ${NORMAL}"
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

// Untuk mencegah bot mengirim pesan berkali-kali pada satu panggilan yang sama
const processedCalls = new Set(); 

async function startBot() {
    const { state, saveCreds } = await useMultiFileAuthState('auth_info_baileys');
    const { version } = await fetchLatestBaileysVersion();

    const sock = makeWASocket({
        version,
        logger: pino({ level: 'silent' }),
        printQRInTerminal: false,
        markOnlineOnConnect: false, // Menjaga notifikasi HP tetap berbunyi
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
            sock.sendPresenceUpdate('unavailable'); // Menjaga agar status tetap offline
        }
    });

    sock.ev.on('call', async (node) => {
        for (let call of node) {
            if (call.status === 'offer') {
                // Cegah spam pesan untuk panggilan yang sama
                if (processedCalls.has(call.id)) continue;
                processedCalls.add(call.id);

                const callerId = call.from;
                const cleanNumber = callerId.split('@')[0].split(':')[0];
                const cleanJid = cleanNumber + '@s.whatsapp.net';

                try {
                    // Tolak panggilan
                    await sock.rejectCall(call.id, callerId);
                    console.log(`[📞] Panggilan otomatis ditolak dari: ${cleanNumber}`);

                    // Kirim pesan peringatan tunggal
                    await sock.sendMessage(cleanJid, { 
                        text: "⚠️ *PENGUMUMAN OTOMATIS*\nMohon maaf, saat ini kami tidak dapat menerima panggilan telepon. Silakan kirimkan pesan teks (chat) saja. Terima kasih." 
                    });

                    // Hapus ID panggilan dari memori setelah 1 menit agar tidak menumpuk
                    setTimeout(() => processedCalls.delete(call.id), 60000);

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
