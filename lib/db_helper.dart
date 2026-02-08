import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() {
    return _instance;
  }

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'alisveris_v3.db'); // v3'e geçtik
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        // 1. Anlık Sepet
        await db.execute(
          "CREATE TABLE sepet(id INTEGER PRIMARY KEY AUTOINCREMENT, fiyat REAL, isim TEXT, adet INTEGER, tarih TEXT)",
        );
        // 2. Geçmiş Fiş Başlıkları (Market adı eklendi)
        await db.execute(
          "CREATE TABLE gecmis(id INTEGER PRIMARY KEY AUTOINCREMENT, market TEXT, tarih TEXT, toplam_tutar REAL, toplam_adet INTEGER)",
        );
        // 3. Geçmiş Fiş Detayları (Hangi fişte hangi ürünler var)
        await db.execute(
          "CREATE TABLE gecmis_detay(id INTEGER PRIMARY KEY AUTOINCREMENT, gecmis_id INTEGER, isim TEXT, fiyat REAL, adet INTEGER)",
        );
      },
    );
  }

  // --- SEPET İŞLEMLERİ ---
  Future<void> urunEkleveyaGuncelle(double fiyat, String tahminiIsim) async {
    final db = await database;
    final List<Map<String, dynamic>> mevcut = await db.query(
      'sepet',
      where: 'fiyat = ?',
      whereArgs: [fiyat],
    );

    if (mevcut.isNotEmpty) {
      int id = mevcut.first['id'];
      int eskiAdet = mevcut.first['adet'];
      await db.update('sepet', {'adet': eskiAdet + 1}, where: 'id = ?', whereArgs: [id]);
    } else {
      await db.insert('sepet', {
        'fiyat': fiyat,
        'isim': tahminiIsim,
        'adet': 1,
        'tarih': DateTime.now().toString(),
      });
    }
  }

  Future<void> adetGuncelle(int id, int yeniAdet) async {
    final db = await database;
    if (yeniAdet <= 0) {
      await db.delete('sepet', where: 'id = ?', whereArgs: [id]);
    } else {
      await db.update('sepet', {'adet': yeniAdet}, where: 'id = ?', whereArgs: [id]);
    }
  }

  Future<void> urunSil(int id) async {
    final db = await database;
    await db.delete('sepet', where: 'id = ?', whereArgs: [id]);
  }
  
  Future<void> urunGeriYukle(double fiyat, String isim, int adet) async {
    final db = await database;
    await db.insert('sepet', {'fiyat': fiyat, 'isim': isim, 'adet': adet, 'tarih': DateTime.now().toString()});
  }

  Future<List<Map<String, dynamic>>> sepetiGetir() async {
    final db = await database;
    return await db.query('sepet', orderBy: "id DESC");
  }

  // --- GELİŞMİŞ GEÇMİŞ İŞLEMLERİ ---

  // 1. Alışverişi Bitir (Hem Başlığı Hem Detayları Kaydet)
  Future<void> alisverisiTamamla(String marketAdi, double toplamTutar, int toplamAdet, List<Map<String, dynamic>> sepetUrunleri) async {
    final db = await database;
    
    // A. Fiş Başlığını Kaydet
    int fisId = await db.insert('gecmis', {
      'market': marketAdi,
      'tarih': DateTime.now().toString(),
      'toplam_tutar': toplamTutar,
      'toplam_adet': toplamAdet
    });

    // B. Sepetteki her ürünü 'gecmis_detay' tablosuna kopyala
    for (var urun in sepetUrunleri) {
      await db.insert('gecmis_detay', {
        'gecmis_id': fisId, // Bu ürünün hangi fişe ait olduğunu belirtiyoruz
        'isim': urun['isim'],
        'fiyat': urun['fiyat'],
        'adet': urun['adet']
      });
    }

    // C. Sepeti Temizle
    await db.delete('sepet');
  }

  // 2. Geçmiş Fiş Listesini Getir
  Future<List<Map<String, dynamic>>> gecmisiGetir() async {
    final db = await database;
    return await db.query('gecmis', orderBy: "tarih DESC");
  }

  // 3. Tıklanan Fişin Detaylarını Getir
  Future<List<Map<String, dynamic>>> fisDetaylariniGetir(int fisId) async {
    final db = await database;
    return await db.query('gecmis_detay', where: 'gecmis_id = ?', whereArgs: [fisId]);
  }
  
  // 4. Grafik Verisi
  Future<List<Map<String, dynamic>>> grafikVerisiGetir() async {
    final db = await database;
    return await db.query('gecmis', orderBy: "tarih ASC", limit: 20);
  }
  
  // Fiş Silme (Detaylarıyla Birlikte)
  Future<void> gecmisSil(int id) async {
     final db = await database;
     await db.delete('gecmis', where: 'id = ?', whereArgs: [id]); // Başlığı sil
     await db.delete('gecmis_detay', where: 'gecmis_id = ?', whereArgs: [id]); // İçindeki ürünleri de sil
  }
}