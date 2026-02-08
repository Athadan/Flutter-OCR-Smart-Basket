import 'dart:async';
import 'dart:io'; 
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart'; 
import 'package:intl/intl.dart'; 
import 'db_helper.dart';

late List<CameraDescription> _cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    _cameras = await availableCameras();
  } catch (e) {
    _cameras = [];
  }
  runApp(const AnaUygulama());
}

class AnaUygulama extends StatelessWidget {
  const AnaUygulama({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.teal),
      home: const AnaEkran(),
    );
  }
}

class AnaEkran extends StatefulWidget {
  const AnaEkran({super.key});
  @override
  State<AnaEkran> createState() => _AnaEkranState();
}

class _AnaEkranState extends State<AnaEkran> {
  int _seciliSayfa = 0;
  
  final List<Widget> _sayfalar = [
    const KameraEkrani(),   
    const GecmisEkrani(),   
    const GrafikEkrani(),   
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _sayfalar[_seciliSayfa],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _seciliSayfa,
        onTap: (index) => setState(() => _seciliSayfa = index),
        selectedItemColor: Colors.teal,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.shopping_cart), label: 'Alışveriş'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Geçmiş'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Analiz'),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------
// 1. SAYFA: KAMERA VE SEPET
// ---------------------------------------------------------
class KameraEkrani extends StatefulWidget {
  const KameraEkrani({super.key});
  @override
  State<KameraEkrani> createState() => _KameraEkraniState();
}

class _KameraEkraniState extends State<KameraEkrani> {
  double? butceLimiti;
  TextEditingController butceController = TextEditingController();
  
  CameraController? controller;
  bool isCameraInitialized = false;
  final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  
  double _currentZoom = 1.0;
  double _baseScale = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;

  double toplamTutar = 0.0;
  int toplamAdet = 0; 
  List<Map<String, dynamic>> sepet = [];
  final dbHelper = DatabaseHelper();
  
  bool isAutoMode = false;
  double? sonEklenenFiyat; 
  DateTime? sonEklemeZamani;
  
  bool isScanning = false;

  @override
  void initState() {
    super.initState();
    initializeCamera();
    verileriYukle();
  }

  void verileriYukle() async {
    final veriler = await dbHelper.sepetiGetir();
    if (!mounted) return;
    setState(() {
      sepet = veriler;
      toplamTutar = sepet.fold(0, (sum, item) => sum + (item['fiyat'] * item['adet']));
      toplamAdet = sepet.fold(0, (sum, item) => sum + (item['adet'] as int));
    });
  }

  void initializeCamera() {
    if (_cameras.isEmpty) return;
    controller = CameraController(_cameras[0], ResolutionPreset.high, enableAudio: false);
    controller!.initialize().then((_) async {
      if (!mounted) return;
      try { await controller!.setFlashMode(FlashMode.off); } catch (e) {}
      _minZoom = await controller!.getMinZoomLevel();
      _maxZoom = await controller!.getMaxZoomLevel();
      setState(() { isCameraInitialized = true; });
    });
  }

  void zoomYap(double deger) {
    if (deger < _minZoom) deger = _minZoom;
    if (deger > _maxZoom) deger = _maxZoom;
    if (deger > 4.0) deger = 4.0; 
    if (controller != null) {
      setState(() { _currentZoom = deger; });
      controller!.setZoomLevel(deger);
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    textRecognizer.close();
    super.dispose();
  }

  Future<void> fiyatiOku() async {
    if (isScanning || controller == null || !controller!.value.isInitialized) return;
    
    setState(() => isScanning = true);
    File? geciciResim;

    try {
      if (controller!.value.flashMode != FlashMode.off) {
        await controller!.setFlashMode(FlashMode.off);
      }

      final image = await controller!.takePicture();
      geciciResim = File(image.path);
      
      final inputImage = InputImage.fromFilePath(image.path);
      final recognizedText = await textRecognizer.processImage(inputImage);

      List<Map<String, dynamic>> fiyatAdaylari = [];
      List<TextBlock> tumBloklar = recognizedText.blocks;

      RegExp fiyatRegex = RegExp(r'(\d+[\.,]\d{2})');
      RegExp safSayi = RegExp(r'^(\d{1,4})[\.,]?$');

      for (TextBlock block in tumBloklar) {
        for (TextLine line in block.lines) {
          String metin = line.text.trim();
          double boyut = line.boundingBox.height;
          if (metin.toLowerCase().contains('tarih') || metin.toLowerCase().contains('kod')) continue;

          double? bulunanFiyat;
          var formatli = fiyatRegex.firstMatch(metin);
          if (formatli != null) {
            String ham = formatli.group(0)!.replaceAll(',', '.');
            bulunanFiyat = double.tryParse(ham);
          } else if (safSayi.hasMatch(metin) && boyut > 50) {
             bulunanFiyat = double.tryParse(metin.replaceAll('.', '').replaceAll(',', ''));
          }

          if (bulunanFiyat != null && bulunanFiyat < 10000 && (bulunanFiyat < 1900 || bulunanFiyat > 2100)) {
            fiyatAdaylari.add({'fiyat': bulunanFiyat, 'boyut': boyut, 'y': block.boundingBox.top});
          }
        }
      }

      if (fiyatAdaylari.isNotEmpty) {
        fiyatAdaylari.sort((a, b) => b['boyut'].compareTo(a['boyut']));
        var kazanan = fiyatAdaylari[0];
        double fiyat = kazanan['fiyat'];
        double fiyatY = kazanan['y'];

        bool spamVar = false;
        if (isAutoMode && sonEklenenFiyat == fiyat) {
           if (sonEklemeZamani != null && DateTime.now().difference(sonEklemeZamani!).inSeconds < 4) spamVar = true;
        }

        if (!spamVar) {
          String tahmin = "Ürün";
          double maxBoyut = 0;
          for (TextBlock block in tumBloklar) {
             if (block.boundingBox.top >= fiyatY - 10) continue;
             for (TextLine line in block.lines) {
                if (line.text.length < 3) continue;
                if (line.boundingBox.height > maxBoyut) {
                  maxBoyut = line.boundingBox.height;
                  tahmin = line.text;
                }
             }
          }
          
          await dbHelper.urunEkleveyaGuncelle(fiyat, tahmin);
          verileriYukle();
          HapticFeedback.heavyImpact();
          if (mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$tahmin ($fiyat TL) Eklendi!"), duration: const Duration(seconds: 1), backgroundColor: Colors.teal));
          }
          
          setState(() { sonEklenenFiyat = fiyat; sonEklemeZamani = DateTime.now(); });
        }
      } 
    } catch (e) {
    } finally {
      if (geciciResim != null && await geciciResim.exists()) await geciciResim.delete();
      if (mounted) setState(() => isScanning = false);
      if (isAutoMode && mounted) {
        Future.delayed(const Duration(milliseconds: 2500), () {
          if (isAutoMode && mounted) fiyatiOku();
        });
      }
    }
  }

  void alisverisiBitir() {
    if (sepet.isEmpty) return;
    
    TextEditingController marketController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Alışverişi Kaydet"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Toplam $toplamAdet ürün, ${toplamTutar.toStringAsFixed(2)} TL."),
            const SizedBox(height: 20),
            TextField(
              controller: marketController,
              decoration: const InputDecoration(
                labelText: "Market Adı",
                hintText: "Örn: Migros, BİM, Pazar...",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.store)
              ),
            )
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("İptal")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
            onPressed: () async {
              String market = marketController.text.isEmpty ? "Genel Market" : marketController.text;
              
              // Sepet listesini de gönderiyoruz ki detaylara kaydedilsin
              await dbHelper.alisverisiTamamla(market, toplamTutar, toplamAdet, sepet);
              
              verileriYukle(); 
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Alışveriş Kaydedildi! ✅")));
            },
            child: const Text("KAYDET"),
          ),
        ],
      ),
    );
  }

  void isimDuzenle(int index) {
    var urun = sepet[index];
    TextEditingController isimController = TextEditingController(text: urun['isim'] ?? "Ürün");
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Ürün İsmini Düzelt"),
        content: TextField(controller: isimController, autofocus: true, decoration: const InputDecoration(hintText: "Doğrusunu yazın", border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("İptal")),
          ElevatedButton(
            onPressed: () async {
              await dbHelper.database.then((db) { db.update('sepet', {'isim': isimController.text}, where: 'id = ?', whereArgs: [urun['id']]); });
              verileriYukle();
              Navigator.pop(context);
            },
            child: const Text("Kaydet"),
          ),
        ],
      ),
    );
  }

  void butceBelirle() {
    showDialog(context: context, builder: (context) => AlertDialog(
      title: const Text("Bütçe Hedefi"),
      content: TextField(controller: butceController, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: "Örn: 2000", suffixText: "TL")),
      actions: [ElevatedButton(onPressed: () {
          if (butceController.text.isNotEmpty) setState(() => butceLimiti = double.tryParse(butceController.text.replaceAll(',', '.')));
          Navigator.pop(context);
      }, child: const Text("Kaydet"))],
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (!isCameraInitialized) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    double ekranGenisligi = MediaQuery.of(context).size.width;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Alışveriş Asistanı"),
        backgroundColor: toplamTutar > (butceLimiti ?? 999999) ? Colors.red : Colors.teal,
        actions: [
          Row(children: [const Text("OTO", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)), Switch(value: isAutoMode, onChanged: (val) { setState(() { isAutoMode = val; sonEklenenFiyat = null; }); if(val) fiyatiOku(); }, activeColor: Colors.orange)]),
          IconButton(icon: const Icon(Icons.account_balance_wallet), onPressed: butceBelirle),
          IconButton(icon: const Icon(Icons.check_circle, color: Colors.white), onPressed: alisverisiBitir, tooltip: "Bitir ve Kaydet"),
        ],
      ),
      backgroundColor: Colors.black,
      body: Column(
        children: [
          if (butceLimiti != null) LinearProgressIndicator(value: (toplamTutar / butceLimiti!).clamp(0.0, 1.0), color: toplamTutar > butceLimiti! ? Colors.red : Colors.teal, minHeight: 8),
          Expanded(flex: 40, child: GestureDetector(
            onScaleStart: (d) => _baseScale = _currentZoom,
            onScaleUpdate: (d) => zoomYap(_baseScale * d.scale),
            child: Stack(children: [
               SizedBox.expand(child: CameraPreview(controller!)),
               Center(child: Container(width: ekranGenisligi * 0.9, height: ekranGenisligi * 0.8, decoration: BoxDecoration(border: Border.all(color: isAutoMode ? Colors.orange : Colors.greenAccent, width: isAutoMode ? 4 : 2), borderRadius: BorderRadius.circular(10)))),
               Center(child: Text("+", style: TextStyle(color: isAutoMode ? Colors.orange : Colors.greenAccent, fontSize: 30))),
               Positioned(right: 20, top: 20, child: Text("${_currentZoom.toStringAsFixed(1)}x", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18, shadows: [Shadow(color: Colors.black, blurRadius: 5)]))),
               if(isAutoMode) Positioned(bottom: 10, left: 0, right: 0, child: Center(child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(5)), child: const Text("OTOMATİK AKTİF", style: TextStyle(fontWeight: FontWeight.bold)))))
            ]),
          )),
          Expanded(flex: 60, child: Container(
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            child: Column(children: [
              Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                 Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("TOPLAM", style: TextStyle(color: Colors.teal)), Text("${toplamTutar.toStringAsFixed(2)} ₺", style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.teal))]),
                 Column(children: [Text("$toplamAdet", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), const Text("Parça", style: TextStyle(color: Colors.grey))])
              ])),
              if(!isAutoMode) Padding(padding: const EdgeInsets.all(10), child: SizedBox(width: double.infinity, height: 50, child: ElevatedButton.icon(onPressed: isScanning ? null : fiyatiOku, style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white), icon: const Icon(Icons.camera_alt), label: Text(isScanning ? "OKUNUYOR..." : "FİYATI EKLE")))),
              Expanded(child: ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 10), itemCount: sepet.length, itemBuilder: (context, index) {
                 var urun = sepet[index];
                 return Dismissible(
                   key: Key(urun['id'].toString()), direction: DismissDirection.endToStart,
                   background: Container(color: Colors.red, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete, color: Colors.white)),
                   onDismissed: (d) async {
                     var silinen = urun; await dbHelper.urunSil(urun['id']); verileriYukle();
                     if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Silindi"), action: SnackBarAction(label: "GERİ AL", onPressed: () async { await dbHelper.urunGeriYukle(silinen['fiyat'], silinen['isim'], silinen['adet']); verileriYukle(); })));
                   },
                   child: Card(child: ListTile(
                     onTap: () => isimDuzenle(index),
                     title: Row(children: [Expanded(child: Text(urun['isim'] ?? "Ürün", maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold))), const Icon(Icons.edit, size: 14, color: Colors.grey)]),
                     subtitle: Text("${urun['fiyat']} ₺"),
                     trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(icon: const Icon(Icons.remove, color: Colors.red), onPressed: () async { await dbHelper.adetGuncelle(urun['id'], urun['adet'] - 1); verileriYukle(); }),
                        Text("${urun['adet']}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        IconButton(icon: const Icon(Icons.add, color: Colors.green), onPressed: () async { await dbHelper.adetGuncelle(urun['id'], urun['adet'] + 1); verileriYukle(); }),
                     ]),
                   )),
                 );
              }))
            ]),
          ))
        ],
      ),
    );
  }
}

// ---------------------------------------------------------
// 2. SAYFA: GEÇMİŞ LİSTESİ (TIKLANABİLİR)
// ---------------------------------------------------------
class GecmisEkrani extends StatefulWidget {
  const GecmisEkrani({super.key});
  @override
  State<GecmisEkrani> createState() => _GecmisEkraniState();
}

class _GecmisEkraniState extends State<GecmisEkrani> {
  List<Map<String, dynamic>> gecmisListe = [];
  final dbHelper = DatabaseHelper();

  @override
  void initState() {
    super.initState();
    verileriYukle();
  }
  
  void verileriYukle() async {
    final veriler = await dbHelper.gecmisiGetir();
    if(mounted) setState(() => gecmisListe = veriler);
  }

  @override
  Widget build(BuildContext context) {
    verileriYukle(); 
    return Scaffold(
      appBar: AppBar(title: const Text("Alışveriş Geçmişi"), backgroundColor: Colors.teal, foregroundColor: Colors.white),
      body: gecmisListe.isEmpty 
        ? const Center(child: Text("Henüz geçmiş kayıt yok.", style: TextStyle(color: Colors.grey)))
        : ListView.builder(
            itemCount: gecmisListe.length,
            itemBuilder: (context, index) {
              var kayit = gecmisListe[index];
              DateTime tarih = DateTime.parse(kayit['tarih']);
              String formatliTarih = DateFormat('dd MMM yyyy, HH:mm').format(tarih);
              
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: ListTile(
                  leading: CircleAvatar(backgroundColor: Colors.teal.shade100, child: const Icon(Icons.receipt_long, color: Colors.teal)),
                  title: Text(kayit['market'] ?? "Market", style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("$formatliTarih\n${kayit['toplam_adet']} Ürün"),
                  isThreeLine: true,
                  trailing: Text("${kayit['toplam_tutar'].toStringAsFixed(2)} ₺", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.teal)),
                  onTap: () {
                    // Detay sayfasına git
                    Navigator.push(context, MaterialPageRoute(builder: (context) => FisDetayEkrani(fisId: kayit['id'], marketAdi: kayit['market'], tutar: kayit['toplam_tutar'])));
                  },
                ),
              );
            },
          ),
    );
  }
}

// ---------------------------------------------------------
// 2.1 YENİ SAYFA: FİŞ DETAYI (İçindeki ürünleri gösterir)
// ---------------------------------------------------------
class FisDetayEkrani extends StatefulWidget {
  final int fisId;
  final String? marketAdi;
  final double tutar;

  const FisDetayEkrani({super.key, required this.fisId, required this.marketAdi, required this.tutar});

  @override
  State<FisDetayEkrani> createState() => _FisDetayEkraniState();
}

class _FisDetayEkraniState extends State<FisDetayEkrani> {
  List<Map<String, dynamic>> urunler = [];
  final dbHelper = DatabaseHelper();

  @override
  void initState() {
    super.initState();
    yukle();
  }

  void yukle() async {
    final veriler = await dbHelper.fisDetaylariniGetir(widget.fisId);
    setState(() => urunler = veriler);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.marketAdi ?? "Fiş Detayı"), backgroundColor: Colors.teal),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            color: Colors.teal.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("TOPLAM TUTAR", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Text("${widget.tutar.toStringAsFixed(2)} TL", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.teal)),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: urunler.length,
              itemBuilder: (context, index) {
                var urun = urunler[index];
                return ListTile(
                  title: Text(urun['isim'], style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("${urun['fiyat']} TL x ${urun['adet']} Adet"),
                  trailing: Text("${(urun['fiyat'] * urun['adet']).toStringAsFixed(2)} TL"),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------
// 3. SAYFA: GRAFİKLER (DÜZELTİLMİŞ)
// ---------------------------------------------------------
class GrafikEkrani extends StatefulWidget {
  const GrafikEkrani({super.key});
  @override
  State<GrafikEkrani> createState() => _GrafikEkraniState();
}

class _GrafikEkraniState extends State<GrafikEkrani> {
  List<Map<String, dynamic>> veriler = [];
  final dbHelper = DatabaseHelper();

  @override
  void initState() {
    super.initState();
    yukle();
  }

  void yukle() async {
    final v = await dbHelper.grafikVerisiGetir();
    if(mounted) setState(() => veriler = v);
  }

  @override
  Widget build(BuildContext context) {
    yukle(); 
    if (veriler.isEmpty) return const Center(child: Text("Grafik için henüz yeterli veri yok."));

    List<FlSpot> noktalar = [];
    double maxTutar = 0;
    
    for (int i = 0; i < veriler.length; i++) {
      double tutar = veriler[i]['toplam_tutar'];
      if (tutar > maxTutar) maxTutar = tutar;
      noktalar.add(FlSpot(i.toDouble(), tutar));
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Harcama Analizi"), backgroundColor: Colors.teal, foregroundColor: Colors.white),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text("Harcama Trendi (Son Alışverişler)", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Expanded(
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(show: true, drawVerticalLine: false), // Sadece yatay çizgiler olsun, daha sade
                  titlesData: FlTitlesData(
                    // SOL EKSEN AYARLARI (Sorunu çözen kısım)
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 46, // Alanı biraz genişlettik
                        getTitlesWidget: (value, meta) {
                          if (value == meta.max || value == meta.min) return const SizedBox(); // En tepe ve en dip çakışmasın
                          
                          String text;
                          if (value >= 1000) {
                            text = '${(value / 1000).toStringAsFixed(1)}k'; // 1500 -> 1.5k
                          } else {
                            text = value.toInt().toString(); // 500.0 -> 500
                          }
                          return Text(text, style: const TextStyle(color: Colors.grey, fontSize: 10), textAlign: TextAlign.right);
                        },
                      ),
                    ),
                    bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), // Alt tarihleri kapattık, sığmıyor
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: true, border: Border.all(color: Colors.grey.shade200)),
                  minX: 0,
                  maxX: (veriler.length - 1).toDouble(),
                  minY: 0,
                  maxY: maxTutar * 1.1, // Tepede %10 boşluk bırak
                  lineBarsData: [
                    LineChartBarData(
                      spots: noktalar,
                      isCurved: true,
                      color: Colors.teal,
                      barWidth: 4,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: true),
                      belowBarData: BarAreaData(show: true, color: Colors.teal.withOpacity(0.2)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}