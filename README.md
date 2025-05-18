# LockSmart - Penyimpanan Berbasis RFID untuk Perlindungan Maksimal

## Anggota Kelompok 
- Alexander Christhian - 2306267025
- Maharaka Fadhilah - 2306225520
- Naufal Hadi Rashikin - 2306231366
- Teufik Ali Hadzalic - 2306267012

## Introduction to the problem and the solution

Dalam dunia saat ini, mengamankan barang berharga, dokumen rahasia, dan peralatan sensitif telah menjadi semakin penting. Sistem kunci konvensional rentan terhadap duplikasi, pencurian, atau kehilangan kunci, yang menciptakan kerentanan keamanan. Selain itu, mengelola kunci fisik untuk berbagai unit penyimpanan bisa merepotkan dan tidak efisien.

LockSmart mengatasi tantangan ini dengan menerapkan sistem autentikasi berbasis RFID untuk penyimpanan yang aman. Sistem ini menyediakan:

- Akses tanpa kunci menggunakan teknologi RFID, menghilangkan masalah terkait dengan kunci fisik
- Mekanisme pembukaan dan penutupan otomatis untuk kenyamanan
- Umpan balik visual dan audio untuk status sistem
- Keamanan yang ditingkatkan melalui autentikasi digital

LockSmart adalah sistem penyimpanan aman yang menggunakan teknologi MFRC522 RFID Reader untuk mengautentikasi akses, memberikan izin masuk hanya kepada tag RFID yang berwenang. Sistem ini menggunakan Motor Servo SG90 untuk mengontrol mekanisme pintu, dengan indikator LED dua warna dan buzzer yang memberikan umpan balik status yang jelas. Sebuah tombol khusus memfasilitasi penutupan pintu, melengkapi solusi penyimpanan yang aman.

## Hardware design and implementation details

### Komponen yang Digunakan
- Mikrokontroler Arduino Uno R3 (ATMega328P)
- Modul MFRC522 RFID Reader
- Motor Servo SG90
- 2 LED warna (Merah dan Hijau)
- Buzzer 
- Button
- Kabel jumper dan breadboard
- Arduino USB Serial Cable
- Resistor (satu 1k Ohm, dua 220 Ohm)

### Diagram Rangkaian

Proteus :
![alt text](<PNG Markdown/Screenshot Rangkaian Proteus.jpg>)

Fisik : 
![alt text](<PNG Markdown/Screenshot Rangkaian Fisik.jpg>)

**NOTE : RANGKAIAN FISIK DAN PROTEUS BERBEDA KARENA KETERBATASAN PADA PROTEUS YANG TIDAK MEMILIKI LIBRARY RFID SEHINGGA HARUS MENGGUNAKAN SERIAL MONITOR**
### Koneksi Perangkat Keras
- MFRC522 RFID Reader:
  - Pin SDA → Pin Digital Arduino 10 (PB2)
  - Pin SCK → Pin Digital Arduino 13 (PB5)
  - Pin MOSI → Pin Digital Arduino 11 (PB3)
  - Pin MISO → Pin Digital Arduino 12 (PB4)
  - 3.3V → Arduino 3.3V
  - GND → Arduino GND

- Motor Servo SG90:
  - Pin Sinyal → Pin Digital Arduino 9 (PB1)
  - VCC → Arduino 5V
  - GND → Arduino GND

- Indikator LED:
  - LED Merah → Pin Analog Arduino 3 (PC3)
  - LED Hijau → Pin Analog Arduino 4 (PC4)
  - GND → Arduino GND (melalui resistor)

- Buzzer:
  - Positif → Pin Analog Arduino 2 (PC2)
  - Negatif → Arduino GND

- Button:
  - Terminal satu → Pin Digital Arduino 7 (PD7)
  - Terminal lain → Arduino 5V
  - Resistor pull-down → GND

## Software implementation details

### Library yang Digunakan
- SPI.h - Untuk komunikasi SPI
- MFRC522.h - Untuk operasi pembaca RFID
- Servo.h - Untuk mengendalikan motor servo

### Algoritma
1. Inisialisasi sistem
   - Konfigurasi pin dan periferal
   - Inisialisasi pembaca RFID
   - Posisikan servo ke posisi tertutup
   - Siapkan indikator LED dan buzzer

2. Loop Utama
   - Periksa keberadaan kartu RFID
   - Jika kartu terdeteksi, verifikasi otorisasi
   - Jika diotorisasi, aktifkan urutan pembukaan
   - Pantau penekanan tombol untuk penutupan pintu
   - Kembali ke keadaan pemantauan

### Autentikasi RFID
Sistem memelihara database UID kartu RFID yang berwenang. Ketika kartu disodorkan, UID-nya dibaca dan dibandingkan dengan database ini. Keberhasilan autentikasi memicu urutan pembukaan pintu, sementara percobaan yang gagal mengaktifkan indikasi penolakan.

### Mekanisme Kontrol Pintu
Motor servo mengontrol mekanisme kunci pintu, berputar ke sudut tertentu untuk posisi mengunci dan membuka kunci. Setelah autentikasi berhasil, servo berputar ke posisi terbuka, memungkinkan akses ke kompartemen penyimpanan.

### Sistem Umpan Balik Pengguna
- LED hijau menyala saat autentikasi berhasil
- LED merah menunjukkan percobaan akses tidak sah
- Buzzer memberikan umpan balik suara - bunyi bip pendek untuk akses berhasil, nada 2x untuk akses ditolak

## Test results and performance evaluation

Gambaran hasil pada rangkaian proteus :
![alt text](<PNG Markdown/Screenshot Proteus Berhasil.jpg>)

Video Hasil pada rangkaian proteus :

https://youtu.be/Z_YuzZstceQ

Video Hasil pada rangkaian fisik : 

https://youtube.com/shorts/x-vl-7Bu4g4?feature=share

## Conclusion and future work

### Kesimpulan
Sistem penyimpanan berbasis RFID LockSmart berhasil mendemonstrasikan solusi efektif untuk kontrol akses penyimpanan yang aman. Dengan menghilangkan kunci fisik dan menerapkan autentikasi digital, sistem memberikan keamanan yang ditingkatkan sambil mempertahankan kenyamanan pengguna. Kombinasi umpan balik visual, audio, dan mekanis menciptakan pengalaman pengguna yang komprehensif yang mengkomunikasikan status sistem dengan jelas.

Prototipe telah terbukti tangguh dalam pengujian, dengan autentikasi dan operasi mekanis yang andal. Desainnya yang modular memungkinkan penyesuaian terhadap berbagai persyaratan penyimpanan dan tingkat keamanan.

### Conclusion and future work
Beberapa peningkatan yang dapat lebih meningkatkan sistem LockSmart:

1. **Integrasi Sensor Suhu dan Kelembapan**: Menerapkan Sensor untuk mendeteksi kondisi dalam kotak penyimpanan

2. **Integrasi Ventilasi Udara**: Memanfaatkan sensor dengan ventilasi untuk memberi udara pada kotak untuk mencegah suhu tinggi dalam kotak
