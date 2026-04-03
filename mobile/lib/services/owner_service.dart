import 'dart:math';
import 'package:flutter/foundation.dart';
import '../main.dart';

class OwnerService {
  // ─── Properties ───

  /// Get all properties owned by the current user
  Future<List<Map<String, dynamic>>> getOwnerProperties() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    debugPrint('[OwnerService] Fetching properties for owner: $userId');
    final response = await supabase.from('properties').select('''
          id, property_name, property_address, total_units, available_units, status,
          floors(id, floor_number, floor_name)
        ''').eq('owner_id', userId).order('property_name');

    debugPrint('[OwnerService] Found ${response.length} properties');
    return List<Map<String, dynamic>>.from(response);
  }

  // ─── Rooms (Units) ───

  /// Get all units for a property with tenant and code info
  Future<List<Map<String, dynamic>>> getUnitsForProperty(
      String propertyId) async {
    debugPrint('[OwnerService] Fetching units for property: $propertyId');
    final response = await supabase.from('units').select('''
          id, unit_number, unit_type, bedrooms, bathrooms, square_feet,
          monthly_rent, is_occupied, max_occupancy, floor_id,
          floors(floor_name, floor_number)
        ''').eq('property_id', propertyId).order('unit_number');

    // Fetch codes and occupants for each unit
    final units = List<Map<String, dynamic>>.from(response);
    for (var i = 0; i < units.length; i++) {
      final unitId = units[i]['id'];

      // Get active code
      final codes = await supabase
          .from('room_codes')
          .select('id, code, max_uses, used_count, is_active')
          .eq('unit_id', unitId)
          .eq('is_active', true)
          .limit(1);

      units[i]['room_code'] = codes.isNotEmpty ? codes[0] : null;

      // Get occupants
      final occupants = await supabase
          .from('tenant_profiles')
          .select('''
            id, tenant_id, room_number, monthly_rent, move_in_date, approval_status,
            user_profiles:tenant_id(full_name, mobile_number, email)
          ''')
          .eq('property_id', propertyId)
          .eq('room_number', units[i]['unit_number'] ?? '');

      units[i]['occupants'] = List<Map<String, dynamic>>.from(occupants);
      units[i]['current_occupancy'] = occupants.length;
    }

    debugPrint('[OwnerService] Found ${units.length} units');
    return units;
  }

  /// Add a new room (unit)
  Future<Map<String, dynamic>> addRoom({
    required String propertyId,
    required String floorId,
    required String roomName,
    int maxOccupancy = 1,
    double? monthlyRent,
    String? unitType,
    int bedrooms = 1,
    int bathrooms = 1,
    double? squareFeet,
  }) async {
    debugPrint(
        '[OwnerService] Adding room: $roomName to property: $propertyId');

    final unit = await supabase
        .from('units')
        .insert({
          'property_id': propertyId,
          'floor_id': floorId,
          'unit_number': roomName,
          'unit_type': unitType,
          'bedrooms': bedrooms,
          'bathrooms': bathrooms,
          'square_feet': squareFeet,
          'monthly_rent': monthlyRent,
          'max_occupancy': maxOccupancy,
          'is_occupied': false,
        })
        .select()
        .single();

    debugPrint('[OwnerService] ✅ Room created: ${unit['id']}');

    // Auto-generate a join code
    final code = await generateRoomCode(unit['id'], maxUses: maxOccupancy);
    unit['room_code'] = code;

    return unit;
  }

  // ─── Room Codes ───

  /// Generate a unique 6-character alphanumeric code for a room
  Future<Map<String, dynamic>> generateRoomCode(String unitId,
      {int maxUses = 1}) async {
    debugPrint('[OwnerService] Generating room code for unit: $unitId');

    // Deactivate any existing codes for this unit
    await supabase
        .from('room_codes')
        .update({'is_active': false}).eq('unit_id', unitId);

    // Generate unique code
    String code = _generateCode();

    final roomCode = await supabase
        .from('room_codes')
        .insert({
          'unit_id': unitId,
          'code': code,
          'max_uses': maxUses,
          'used_count': 0,
          'is_active': true,
        })
        .select()
        .single();

    debugPrint('[OwnerService] ✅ Generated code: $code for unit: $unitId');
    return roomCode;
  }

  /// Get active code for a room
  Future<Map<String, dynamic>?> getRoomCode(String unitId) async {
    final codes = await supabase
        .from('room_codes')
        .select()
        .eq('unit_id', unitId)
        .eq('is_active', true)
        .limit(1);

    return codes.isNotEmpty ? Map<String, dynamic>.from(codes[0]) : null;
  }

  /// Generate 6-char alphanumeric code
  String _generateCode() {
    const chars =
        'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // Excluded I,O,0,1 to avoid confusion
    final rng = Random.secure();
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  // ─── Tenant Management ───

  /// Get occupants for a specific unit
  Future<List<Map<String, dynamic>>> getRoomOccupants(String unitId) async {
    debugPrint('[OwnerService] Fetching occupants for unit: $unitId');

    // First get the unit details
    final unit = await supabase
        .from('units')
        .select('unit_number, property_id')
        .eq('id', unitId)
        .single();

    final occupants = await supabase
        .from('tenant_profiles')
        .select('''
          id, tenant_id, room_number, monthly_rent, move_in_date, approval_status,
          photo_id_url, live_photo_url,
          user_profiles:tenant_id(full_name, mobile_number, email)
        ''')
        .eq('property_id', unit['property_id'])
        .eq('room_number', unit['unit_number'] ?? '');

    debugPrint('[OwnerService] Found ${occupants.length} occupants');
    return List<Map<String, dynamic>>.from(occupants);
  }

  /// Remove a tenant from a room — archives to past_tenants first
  Future<void> removeTenant(String tenantProfileId, String unitId) async {
    debugPrint(
        '[OwnerService] Removing tenant profile: $tenantProfileId from unit: $unitId');

    // 1. Fetch tenant details before deleting
    final tenantData = await supabase.from('tenant_profiles').select('''
          id, tenant_id, room_number, monthly_rent, move_in_date,
          photo_id_url, live_photo_url, property_id,
          user_profiles:tenant_id(full_name, mobile_number, email)
        ''').eq('id', tenantProfileId).single();

    final profile = tenantData['user_profiles'] as Map<String, dynamic>?;

    // 2. Archive to past_tenants
    try {
      await supabase.from('past_tenants').insert({
        'tenant_id': tenantData['tenant_id'],
        'property_id': tenantData['property_id'],
        'unit_id': unitId,
        'room_number': tenantData['room_number'],
        'tenant_name': profile?['full_name'] ?? 'Unknown',
        'tenant_mobile': profile?['mobile_number'],
        'tenant_email': profile?['email'],
        'monthly_rent': tenantData['monthly_rent'],
        'move_in_date': tenantData['move_in_date'],
        'move_out_date': DateTime.now().toIso8601String().split('T')[0],
        'removal_reason': 'vacated',
        'photo_id_url': tenantData['photo_id_url'],
        'live_photo_url': tenantData['live_photo_url'],
      });
      debugPrint('[OwnerService] ✅ Tenant archived to past_tenants');
    } catch (e) {
      debugPrint('[OwnerService] ⚠️ Failed to archive tenant: $e');
      // Continue with deletion even if archiving fails
    }

    // 3. Delete tenant profile
    await supabase.from('tenant_profiles').delete().eq('id', tenantProfileId);

    // 4. Decrement used_count on the room code
    final codes = await supabase
        .from('room_codes')
        .select('id, used_count')
        .eq('unit_id', unitId)
        .eq('is_active', true)
        .limit(1);

    if (codes.isNotEmpty) {
      final newCount = (codes[0]['used_count'] as int) - 1;
      await supabase.from('room_codes').update(
          {'used_count': newCount < 0 ? 0 : newCount}).eq('id', codes[0]['id']);
    }

    // 5. Check if room is now empty → mark as unoccupied
    final remainingOccupants = await getRoomOccupants(unitId);
    if (remainingOccupants.isEmpty) {
      await supabase
          .from('units')
          .update({'is_occupied': false}).eq('id', unitId);
    }

    debugPrint('[OwnerService] ✅ Tenant removed and archived');
  }

  /// Get past tenants history for a room
  Future<List<Map<String, dynamic>>> getPastTenants(String unitId) async {
    debugPrint('[OwnerService] Fetching past tenants for unit: $unitId');
    final response = await supabase
        .from('past_tenants')
        .select()
        .eq('unit_id', unitId)
        .order('move_out_date', ascending: false);

    debugPrint('[OwnerService] Found ${response.length} past tenants');
    return List<Map<String, dynamic>>.from(response);
  }

  // ─── Room Code: Tenant Side ───

  /// Validate a room code and return room/property info
  Future<Map<String, dynamic>?> validateRoomCode(String code) async {
    debugPrint('[OwnerService] Validating room code: $code');
    final codes = await supabase
        .from('room_codes')
        .select('id, unit_id, max_uses, used_count, is_active')
        .eq('code', code.toUpperCase().trim())
        .eq('is_active', true)
        .limit(1);

    if (codes.isEmpty) {
      debugPrint('[OwnerService] ❌ Code not found or inactive');
      return null;
    }

    final roomCode = codes[0];

    // Check occupancy limit
    if ((roomCode['used_count'] as int) >= (roomCode['max_uses'] as int)) {
      debugPrint('[OwnerService] ❌ Room is full');
      return {'error': 'Room is full — maximum occupancy reached'};
    }

    // Fetch unit + property details
    final unit = await supabase
        .from('units')
        .select('''
          id, unit_number, unit_type, monthly_rent, max_occupancy,
          property_id,
          properties:property_id(property_name, property_address, owner_id)
        ''')
        .eq('id', roomCode['unit_id'])
        .single();

    debugPrint('[OwnerService] ✅ Code valid: Room ${unit['unit_number']}');
    return {
      'room_code': roomCode,
      'unit': unit,
      'property_name': unit['properties']?['property_name'],
      'property_address': unit['properties']?['property_address'],
      'unit_number': unit['unit_number'],
      'monthly_rent': unit['monthly_rent'],
      'property_id': unit['property_id'],
      'unit_id': unit['id'],
    };
  }

  /// Tenant joins a room using a code — creates pending tenant_profile
  Future<void> joinRoomWithCode({
    required String code,
    required String tenantId,
    required String propertyId,
    required String roomNumber,
    required double monthlyRent,
    DateTime? moveInDate,
    String? idProofUrl,
    String? photoUrl,
  }) async {
    debugPrint('[OwnerService] Joining room with code: $code for tenant: $tenantId');

    await supabase.from('tenant_profiles').insert({
      'tenant_id': tenantId,
      'property_id': propertyId,
      'room_number': roomNumber,
      'monthly_rent': monthlyRent,
      'security_deposit': 0.0,
      'move_in_date': (moveInDate ?? DateTime.now()).toIso8601String().split('T')[0],
      'lease_start_date': (moveInDate ?? DateTime.now()).toIso8601String().split('T')[0],
      'approval_status': 'pending',
      'photo_id_url': idProofUrl,
      'live_photo_url': photoUrl,
    });

    debugPrint('[OwnerService] ✅ Tenant profile created with status: pending');
  }

  // ─── Approval Flow: Owner Side ───

  /// Get pending registration requests for owner's properties
  Future<List<Map<String, dynamic>>> getPendingRegistrations() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return [];

    debugPrint('[OwnerService] Fetching pending registrations...');
    final properties = await supabase
        .from('properties')
        .select('id')
        .eq('owner_id', userId);

    if (properties.isEmpty) return [];

    final propertyIds = (properties as List).map((p) => p['id']).toList();

    final pending = await supabase
        .from('tenant_profiles')
        .select('''
          id, tenant_id, property_id, room_number, monthly_rent,
          move_in_date, approval_status, photo_id_url, live_photo_url,
          user_profiles:tenant_id(full_name, mobile_number, email),
          properties:property_id(property_name)
        ''')
        .inFilter('property_id', propertyIds)
        .eq('approval_status', 'pending')
        .order('created_at', ascending: false);

    debugPrint('[OwnerService] Found ${pending.length} pending registrations');
    return List<Map<String, dynamic>>.from(pending);
  }

  /// Approve a tenant registration
  Future<void> approveRegistration(String tenantProfileId) async {
    debugPrint('[OwnerService] Approving tenant: $tenantProfileId');

    // Get tenant profile to find unit
    final profile = await supabase
        .from('tenant_profiles')
        .select('room_number, property_id')
        .eq('id', tenantProfileId)
        .single();

    // Update approval status
    await supabase
        .from('tenant_profiles')
        .update({'approval_status': 'approved'})
        .eq('id', tenantProfileId);

    // Find the unit and increment room code used_count
    final units = await supabase
        .from('units')
        .select('id')
        .eq('property_id', profile['property_id'])
        .eq('unit_number', profile['room_number']);

    if (units.isNotEmpty) {
      final unitId = units[0]['id'];

      // Mark unit as occupied
      await supabase
          .from('units')
          .update({'is_occupied': true})
          .eq('id', unitId);

      // Increment used_count on active code
      final codes = await supabase
          .from('room_codes')
          .select('id, used_count')
          .eq('unit_id', unitId)
          .eq('is_active', true)
          .limit(1);

      if (codes.isNotEmpty) {
        await supabase
            .from('room_codes')
            .update({'used_count': (codes[0]['used_count'] as int) + 1})
            .eq('id', codes[0]['id']);
      }
    }

    debugPrint('[OwnerService] ✅ Registration approved');
  }

  /// Reject a tenant registration
  Future<void> rejectRegistration(String tenantProfileId) async {
    debugPrint('[OwnerService] Rejecting tenant: $tenantProfileId');

    await supabase
        .from('tenant_profiles')
        .update({'approval_status': 'rejected'})
        .eq('id', tenantProfileId);

    debugPrint('[OwnerService] ✅ Registration rejected');
  }

  // ─── Maintenance ───

  /// Get pending maintenance request count for owner's properties
  Future<int> getPendingMaintenanceCount() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return 0;

    try {
      final properties =
          await supabase.from('properties').select('id').eq('owner_id', userId);

      if (properties.isEmpty) return 0;

      final propertyIds = (properties as List).map((p) => p['id']).toList();

      final requests = await supabase
          .from('maintenance_requests')
          .select('id')
          .inFilter('property_id', propertyIds)
          .eq('status', 'pending');

      debugPrint('[OwnerService] Pending maintenance: ${requests.length}');
      return requests.length;
    } catch (e) {
      debugPrint('[OwnerService] ⚠️ Error fetching maintenance count: $e');
      return 0;
    }
  }

  /// Get all maintenance requests for owner's properties
  Future<List<Map<String, dynamic>>> getMaintenanceRequests() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return [];

    final properties =
        await supabase.from('properties').select('id').eq('owner_id', userId);

    if (properties.isEmpty) return [];

    final propertyIds = (properties as List).map((p) => p['id']).toList();

    final requests = await supabase
        .from('maintenance_requests')
        .select('''
          *,
          user_profiles:tenant_id(full_name, mobile_number),
          properties:property_id(property_name)
        ''')
        .inFilter('property_id', propertyIds)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(requests);
  }

  // ─── Dashboard Stats ───

  Future<Map<String, dynamic>> getDashboardStats() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    final properties =
        await supabase.from('properties').select('id').eq('owner_id', userId);

    int totalRooms = 0;
    int occupiedRooms = 0;
    double totalIncome = 0;

    for (final prop in properties) {
      final units = await supabase
          .from('units')
          .select('id, is_occupied, monthly_rent')
          .eq('property_id', prop['id']);

      totalRooms += units.length;
      for (final u in units) {
        if (u['is_occupied'] == true) {
          occupiedRooms++;
          totalIncome += (u['monthly_rent'] as num?)?.toDouble() ?? 0;
        }
      }
    }

    final maintenanceCount = await getPendingMaintenanceCount();

    return {
      'totalRooms': totalRooms,
      'occupiedRooms': occupiedRooms,
      'vacantRooms': totalRooms - occupiedRooms,
      'monthlyIncome': totalIncome,
      'pendingMaintenance': maintenanceCount,
      'totalProperties': properties.length,
    };
  }
}
