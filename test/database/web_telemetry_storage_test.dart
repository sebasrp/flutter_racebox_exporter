import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_racebox_exporter/database/web_telemetry_storage.dart';
import 'package:flutter_racebox_exporter/racebox_ble/models/racebox_data.dart';
import 'package:flutter_racebox_exporter/racebox_ble/models/gps_data.dart';
import 'package:flutter_racebox_exporter/racebox_ble/models/motion_data.dart';

void main() {
  group('WebTelemetryStorage - markAsSynced Bug Fix', () {
    late WebTelemetryStorage storage;

    setUp(() {
      storage = WebTelemetryStorage(bufferCapacity: 100);
    });

    tearDown(() async {
      await storage.close();
    });

    test('should remove synced records from buffer', () async {
      // Create test data
      final testData1 = RaceboxData(
        iTOW: 1000,
        timestamp: DateTime.now(),
        gps: GpsData(
          latitude: 1.0,
          longitude: 2.0,
          wgsAltitude: 100.0,
          mslAltitude: 95.0,
          speed: 10.0,
          heading: 45.0,
          numSatellites: 12,
          fixStatus: 3,
          horizontalAccuracy: 2.0,
          verticalAccuracy: 3.0,
          speedAccuracy: 0.5,
          headingAccuracy: 1.0,
          pdop: 1.5,
          isFixValid: true,
        ),
        motion: MotionData(
          gForceX: 0.1,
          gForceY: 0.2,
          gForceZ: 1.0,
          rotationX: 0.0,
          rotationY: 0.0,
          rotationZ: 0.0,
        ),
        battery: 85.0,
        isCharging: false,
        timeAccuracy: 100,
        validityFlags: 255,
      );

      final testData2 = RaceboxData(
        iTOW: 2000,
        timestamp: DateTime.now(),
        gps: GpsData(
          latitude: 1.1,
          longitude: 2.1,
          wgsAltitude: 101.0,
          mslAltitude: 96.0,
          speed: 11.0,
          heading: 46.0,
          numSatellites: 12,
          fixStatus: 3,
          horizontalAccuracy: 2.0,
          verticalAccuracy: 3.0,
          speedAccuracy: 0.5,
          headingAccuracy: 1.0,
          pdop: 1.5,
          isFixValid: true,
        ),
        motion: MotionData(
          gForceX: 0.1,
          gForceY: 0.2,
          gForceZ: 1.0,
          rotationX: 0.0,
          rotationY: 0.0,
          rotationZ: 0.0,
        ),
        battery: 85.0,
        isCharging: false,
        timeAccuracy: 100,
        validityFlags: 255,
      );

      // Insert records with specific local IDs
      await storage.insertTelemetry(testData1, localId: 'test-id-1');
      await storage.insertTelemetry(testData2, localId: 'test-id-2');

      // Verify records are in buffer
      final pendingBefore = await storage.getPendingTelemetry();
      expect(pendingBefore.length, equals(2));
      expect(await storage.getPendingCount(), equals(2));

      // Mark first record as synced
      final markedCount = await storage.markAsSynced(['test-id-1'], [100]);

      // Verify: record was marked
      expect(markedCount, equals(1));

      // Verify: record was actually removed from buffer (this was the bug!)
      final pendingAfter = await storage.getPendingTelemetry();
      expect(
        pendingAfter.length,
        equals(1),
        reason: 'Should have 1 record remaining after marking 1 as synced',
      );
      expect(await storage.getPendingCount(), equals(1));

      // Verify: the remaining record is the correct one
      expect(pendingAfter.first['local_id'], equals('test-id-2'));

      // Verify: stats were updated
      final stats = await storage.getSyncStats();
      expect(stats['pending_count'], equals(1));
      expect(stats['synced_count'], equals(1));
    });

    test('should remove multiple synced records from buffer', () async {
      // Insert 5 records
      for (int i = 0; i < 5; i++) {
        final data = RaceboxData(
          iTOW: 1000 + i,
          timestamp: DateTime.now(),
          gps: GpsData(
            latitude: 1.0 + i,
            longitude: 2.0 + i,
            wgsAltitude: 100.0,
            mslAltitude: 95.0,
            speed: 10.0,
            heading: 45.0,
            numSatellites: 12,
            fixStatus: 3,
            horizontalAccuracy: 2.0,
            verticalAccuracy: 3.0,
            speedAccuracy: 0.5,
            headingAccuracy: 1.0,
            pdop: 1.5,
            isFixValid: true,
          ),
          motion: MotionData(
            gForceX: 0.1,
            gForceY: 0.2,
            gForceZ: 1.0,
            rotationX: 0.0,
            rotationY: 0.0,
            rotationZ: 0.0,
          ),
          battery: 85.0,
          isCharging: false,
          timeAccuracy: 100,
          validityFlags: 255,
        );
        await storage.insertTelemetry(data, localId: 'test-id-$i');
      }

      expect(await storage.getPendingCount(), equals(5));

      // Mark 3 records as synced
      final markedCount = await storage.markAsSynced(
        ['test-id-0', 'test-id-1', 'test-id-2'],
        [100, 101, 102],
      );

      expect(markedCount, equals(3));
      expect(
        await storage.getPendingCount(),
        equals(2),
        reason: 'Should have 2 records remaining after marking 3 as synced',
      );

      // Verify remaining records are the correct ones
      final pending = await storage.getPendingTelemetry();
      final remainingIds = pending.map((r) => r['local_id']).toList();
      expect(remainingIds, containsAll(['test-id-3', 'test-id-4']));
      expect(remainingIds, isNot(contains('test-id-0')));
      expect(remainingIds, isNot(contains('test-id-1')));
      expect(remainingIds, isNot(contains('test-id-2')));
    });

    test('should not fail when marking non-existent records', () async {
      // Insert one record
      final data = RaceboxData(
        iTOW: 1000,
        timestamp: DateTime.now(),
        gps: GpsData(
          latitude: 1.0,
          longitude: 2.0,
          wgsAltitude: 100.0,
          mslAltitude: 95.0,
          speed: 10.0,
          heading: 45.0,
          numSatellites: 12,
          fixStatus: 3,
          horizontalAccuracy: 2.0,
          verticalAccuracy: 3.0,
          speedAccuracy: 0.5,
          headingAccuracy: 1.0,
          pdop: 1.5,
          isFixValid: true,
        ),
        motion: MotionData(
          gForceX: 0.1,
          gForceY: 0.2,
          gForceZ: 1.0,
          rotationX: 0.0,
          rotationY: 0.0,
          rotationZ: 0.0,
        ),
        battery: 85.0,
        isCharging: false,
        timeAccuracy: 100,
        validityFlags: 255,
      );
      await storage.insertTelemetry(data, localId: 'test-id-1');

      // Try to mark non-existent record
      final markedCount = await storage.markAsSynced(
        ['non-existent-id'],
        [100],
      );

      // Should not throw, just return 0
      expect(markedCount, equals(0));
      expect(
        await storage.getPendingCount(),
        equals(1),
        reason: 'Original record should still be there',
      );
    });
  });
}
