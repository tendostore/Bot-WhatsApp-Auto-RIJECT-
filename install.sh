#!/bin/bash
set -uo pipefail

HIJAU='\033[0;32m'
BIRU='\033[0;34m'
KUNING='\033[1;33m'
MERAH='\033[0;31m'
NORMAL='\033[0m'

BOT_DIR="wa-bot-anticall"

clear
echo -e "${BIRU}==============================================${NORMAL}"
echo -e "${HIJAU}   AUTO-INSTALL WA BOT ANTI-CALL (PPOB & CONFIG) ${NORMAL}"
echo -e "${BIRU}==============================================${NORMAL}"

# 1. Update Node.js ke versi 22 LTS & Install PM2
echo -e "${KUNING}[*] Mengecek & Mengupdate sistem VPS...${NORMAL}"
if command -v node &> /dev/null; then
    NODE_VER=$(node -v | cut -d 'v' -f 2 | cut -d '.' -f 1)
    [[ "$NODE_VER" =~ ^[0-9]+$ ]] || NODE_VER=0
else
    NODE_VER=0
fi

if [ "$NODE_VER" -lt 22 ]; then
    echo -e "${KUNING}[*] Memasang Node.js 22 LTS (terbaru)...${NORMAL}"
    if command -v apt &> /dev/null; then
        apt-get update -y && apt-get install -y curl git build-essential
        curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
        apt-get install -y nodejs
    elif command -v pkg &> /dev/null; then
        pkg update -y && pkg install nodejs git curl -y
    else
        echo -e "${MERAH}[!] Tidak ditemukan apt maupun pkg. Install Node.js 22 secara manual lalu jalankan ulang skrip ini.${NORMAL}"
        exit 1
    fi

    if ! command -v node &> /dev/null; then
        echo -e "${MERAH}[!] Instalasi Node.js gagal. Periksa koneksi/log di atas.${NORMAL}"
        exit 1
    fi
else
    echo -e "${HIJAU}[✓] Node.js v${NODE_VER} sudah terpasang.${NORMAL}"
fi

if ! command -v pm2 &> /dev/null; then
    echo -e "${KUNING}[*] Memasang PM2 secara global...${NORMAL}"
    PM2_LOG=$(mktemp)
    if ! npm install -g pm2 > "$PM2_LOG" 2>&1; then
        echo -e "${MERAH}[!] Gagal memasang PM2. 5 baris log terakhir:${NORMAL}"
        tail -5 "$PM2_LOG"
        rm -f "$PM2_LOG"
        exit 1
    fi
    rm -f "$PM2_LOG"
else
    echo -e "${HIJAU}[✓] PM2 sudah terpasang.${NORMAL}"
fi

# 2. Setup Folder & File
echo -e "${KUNING}[*] Menyiapkan folder bot...${NORMAL}"
rm -rf "$BOT_DIR"
if ! mkdir -p "$BOT_DIR"; then
    echo -e "${MERAH}[!] Gagal membuat folder ${BOT_DIR}. Periksa permission direktori ini.${NORMAL}"
    exit 1
fi
cd "$BOT_DIR" || { echo -e "${MERAH}[!] Gagal masuk ke folder ${BOT_DIR}.${NORMAL}"; exit 1; }

cat << 'EOF' > package.json
{
  "name": "wa-bot-anticall",
  "version": "1.0.0",
  "description": "WhatsApp Bot Anti-Call",
  "main": "index.js",
  "engines": {
    "node": ">=22.0.0"
  },
  "dependencies": {
    "@whiskeysockets/baileys": "6.7.23",
    "pino": "^9.6.0"
  }
}
EOF

cat << 'EOF' > index.js
const {
    default: makeWASocket,
    useMultiFileAuthState,
    DisconnectReason,
    fetchLatestBaileysVersion,
    makeCacheableSignalKeyStore,
    Browsers
} = require('@whiskeysockets/baileys');
const pino = require('pino');
const readline = require('readline');
const fs = require('fs');

const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
const question = (text) => new Promise((resolve) => rl.question(text, resolve));

// Nomor admin/owner yang panggilannya TIDAK ditolak & TIDAK dibalas otomatis.
// Isi via env ADMIN_NUMBERS, format: "628123456789,628987654321" (tanpa +, pisah koma)
const ADMIN_NUMBERS = (process.env.ADMIN_NUMBERS || '')
    .split(',')
    .map(n => n.replace(/[^0-9]/g, ''))
    .filter(Boolean);

const processedCalls = new Set();
const lastReplyAt = new Map(); // JID -> timestamp, untuk cegah spam balasan
const REPLY_COOLDOWN_MS = 5 * 60 * 1000; // 1 balasan per nomor per 5 menit
const isSetupMode = process.env.SETUP_MODE === 'true';

let reconnectAttempts = 0;
const MAX_RECONNECT = 5;

function secureAuthFolder() {
    try {
        fs.chmodSync('auth_info_baileys', 0o700);
        for (const f of fs.readdirSync('auth_info_baileys')) {
            fs.chmodSync(`auth_info_baileys/${f}`, 0o600);
        }
    } catch (e) {
        // folder mungkin belum ada di percobaan pertama, aman diabaikan
    }
}

async function startBot() {
    const { state, saveCreds } = await useMultiFileAuthState('auth_info_baileys');
    secureAuthFolder();
    const { version, isLatest } = await fetchLatestBaileysVersion();
    console.log(`[*] Menggunakan WA Web v${version.join('.')} ${isLatest ? '(terbaru)' : '(perlu update)'}`);

    const sock = makeWASocket({
        version,
        logger: pino({ level: 'silent' }),
        printQRInTerminal: false,
        markOnlineOnConnect: false,  // Notifikasi HP tetap bunyi
        syncFullHistory: false,       // Hemat RAM, tidak narik chat lama
        auth: {
            creds: state.creds,
            keys: makeCacheableSignalKeyStore(state.keys, pino({ level: 'silent' })),
        },
        browser: Browsers.ubuntu('Chrome'), // fingerprint ikut versi library, tidak jadi basi
        getMessage: async () => ({ conversation: '' }),
    });

    if (!sock.authState.creds.registered) {
        console.clear();
        console.log('========================================');
        console.log('   WHATSAPP BOT ANTI-CALL PAIRING');
        console.log('========================================\n');
        const phoneNumber = await question('Masukkan nomor WA (Contoh: 62812xxx): ');
        const code = await sock.requestPairingCode(phoneNumber.replace(/[^0-9]/g, ''));
        console.log(`\n> KODE PAIRING ANDA: ${code} <\n`);
        console.log('Masukkan kode di atas pada WhatsApp HP Anda.');
    }

    sock.ev.on('creds.update', async () => {
        await saveCreds();
        secureAuthFolder();
    });

    sock.ev.on('connection.update', async (update) => {
        const { connection, lastDisconnect } = update;

        if (connection === 'close') {
            const statusCode = lastDisconnect?.error?.output?.statusCode;
            const isLoggedOut = statusCode === DisconnectReason.loggedOut;

            if (isLoggedOut) {
                console.log('[!] Sesi berakhir (logout dari HP). Menghapus sesi lama...');
                try {
                    fs.rmSync('auth_info_baileys', { recursive: true, force: true });
                } catch (e) {
                    console.log('[!] Gagal menghapus folder sesi:', e.message);
                }
                console.log('[!] Jalankan ulang instalasi/pairing secara manual: SETUP_MODE=true node index.js');
                console.log('[!] Bot dihentikan agar PM2 tidak loop restart dengan sesi tidak valid.');
                process.exit(1);
            }

            if (reconnectAttempts < MAX_RECONNECT) {
                reconnectAttempts++;
                const delay = reconnectAttempts * 3000;
                console.log(`[*] Koneksi terputus. Mencoba ulang ke-${reconnectAttempts} dalam ${delay / 1000}s...`);
                setTimeout(startBot, delay);
            } else {
                console.log('[!] Gagal reconnect setelah 5 percobaan. Mohon restart manual.');
                process.exit(1);
            }
        } else if (connection === 'open') {
            reconnectAttempts = 0;
            console.log('\n✅ Bot Berhasil Terhubung ke WhatsApp!');
            await sock.sendPresenceUpdate('unavailable');

            if (isSetupMode) {
                console.log('[*] Memindahkan bot ke background (PM2) dalam 3 detik...');
                setTimeout(() => { process.exit(0); }, 3000);
            }
        }
    });

    sock.ev.on('call', async (callList) => {
        for (const call of callList) {
            if (call.status !== 'offer') continue;
            if (processedCalls.has(call.id)) continue;
            processedCalls.add(call.id);

            const callerJid = call.from;
            const callerNumber = callerJid.split('@')[0];

            if (ADMIN_NUMBERS.includes(callerNumber)) {
                console.log(`[i] Panggilan dari nomor admin ${callerNumber}, dibiarkan (tidak ditolak).`);
                setTimeout(() => processedCalls.delete(call.id), 10000);
                continue;
            }

            try {
                await sock.rejectCall(call.id, callerJid);

                const now = Date.now();
                const last = lastReplyAt.get(callerJid) || 0;
                if (now - last >= REPLY_COOLDOWN_MS) {
                    const timeNow = new Date().toLocaleTimeString('id-ID', { timeZone: 'Asia/Jakarta' });
                    const pesan = `⚠️ *PANGGILAN OTOMATIS DITOLAK*\n\nHalo! 🙏 Untuk mempercepat proses pengisian paket data dan pembuatan config, kami tidak menerima telepon. Silakan langsung ketik pesanan kamu di sini. Admin akan segera memprosesnya! 🚀\n\n_Ditolak pada: ${timeNow}_`;
                    await sock.sendMessage(callerJid, { text: pesan });
                    lastReplyAt.set(callerJid, now);
                } else {
                    console.log(`[i] Panggilan dari ${callerNumber} ditolak (balasan di-skip, masih cooldown).`);
                }

                setTimeout(() => processedCalls.delete(call.id), 10000);
            } catch (e) {
                console.log(`[!] Gagal memproses panggilan dari ${callerJid}:`, e.message);
            }
        }
    });
}

startBot().catch((err) => {
    console.error('[FATAL] Bot crash:', err.message);
    process.exit(1);
});
EOF

# 3. Instalasi Modul (versi stabil)
echo -e "${KUNING}[*] Menginstal library Baileys 6.7.23 (stabil)...${NORMAL}"
if ! npm install --omit=dev 2>&1 | tail -3; then
    echo -e "${MERAH}[!] npm install gagal. Periksa log di atas.${NORMAL}"
    exit 1
fi

# Validasi file
echo -e "${KUNING}[*] Memvalidasi syntax index.js...${NORMAL}"
if node --check index.js; then
    echo -e "${HIJAU}[✓] Syntax OK${NORMAL}"
else
    echo -e "${MERAH}[!] Syntax error pada index.js!${NORMAL}"
    exit 1
fi

# 4. Login Pertama (Mode Setup)
echo -e "${HIJAU}>>> MEMULAI PROSES PAIRING <<<${NORMAL}"
echo -e "${KUNING}[i] Tips: isi variabel ADMIN_NUMBERS (nomor tanpa +, pisah koma) sebelum menjalankan skrip ini jika ingin nomor tertentu tidak diblokir/dibalas otomatis.${NORMAL}"
if ! SETUP_MODE=true ADMIN_NUMBERS="${ADMIN_NUMBERS:-}" node index.js; then
    echo -e "${MERAH}[!] Proses pairing gagal atau dibatalkan. Instalasi dihentikan.${NORMAL}"
    exit 1
fi

# 5. Otomatisasi PM2
echo -e "${KUNING}[*] Mendaftarkan bot ke PM2 agar aktif 24 Jam...${NORMAL}"
pm2 delete bot-wa &> /dev/null || true
pm2 start index.js --name "bot-wa" --restart-delay 5000 --max-restarts 10 \
    ${ADMIN_NUMBERS:+--env ADMIN_NUMBERS="$ADMIN_NUMBERS"}
pm2 save

echo -e "${KUNING}[*] Mengonfigurasi PM2 agar auto-start setelah reboot VPS...${NORMAL}"
STARTUP_CMD=$(pm2 startup 2>&1 | grep -E '^(sudo )?env ' || true)
if [ -n "$STARTUP_CMD" ]; then
    if eval "$STARTUP_CMD"; then
        echo -e "${HIJAU}[✓] Auto-start PM2 berhasil dikonfigurasi.${NORMAL}"
    else
        echo -e "${MERAH}[!] Gagal menjalankan perintah auto-start otomatis. Jalankan manual:${NORMAL}"
        echo "    $STARTUP_CMD"
    fi
else
    echo -e "${MERAH}[!] Tidak bisa mendeteksi perintah startup PM2 otomatis. Jalankan 'pm2 startup' manual dan ikuti instruksinya.${NORMAL}"
fi

clear
echo -e "${HIJAU}==============================================${NORMAL}"
echo -e "${HIJAU}      INSTALASI SELESAI & BOT AKTIF 24 JAM!   ${NORMAL}"
echo -e "${HIJAU}==============================================${NORMAL}"
echo -e "${BIRU}Versi terpasang:${NORMAL}"
echo -e "  Node.js  : $(node -v)"
echo -e "  npm      : $(npm -v)"
echo -e "  PM2      : $(pm2 -v)"
echo -e "  Baileys  : 6.7.23 (stable)"
echo ""
echo -e "${BIRU}Status PM2:${NORMAL}"
pm2 status bot-wa
echo -e "\n${KUNING}VPS atau Terminal sudah bisa Anda tutup. Bot akan terus berjalan menjaga toko Anda!${NORMAL}"
