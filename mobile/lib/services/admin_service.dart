import '../main.dart';

class AdminService {
  // Get dashboard stats
  Future<Map<String, dynamic>> getDashboardStats() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    // Get properties owned by this user
    final properties =
        await supabase.from('properties').select('id').eq('owner_id', userId);

    final propertyIds = properties.map((p) => p['id']).toList();

    if (propertyIds.isEmpty) {
      return {
        'totalTenants': 0,
        'pendingApprovals': 0,
        'pendingPayments': {'count': 0, 'total': 0.0},
        'occupancy': {'total': 0, 'occupied': 0, 'rate': 0},
      };
    }

    // Total approved tenants
    final tenants = await supabase
        .from('tenant_profiles')
        .select('id')
        .inFilter('property_id', propertyIds)
        .eq('approval_status', 'approved');

    // Pending approvals
    final pendingApprovals = await supabase
        .from('tenant_profiles')
        .select('id')
        .inFilter('property_id', propertyIds)
        .eq('approval_status', 'pending');

    // Pending payments
    final pendingPayments = await supabase
        .from('payments')
        .select('id, total_amount')
        .inFilter('property_id', propertyIds)
        .eq('payment_status', 'pending');

    double totalPending = 0;
    for (var p in pendingPayments) {
      totalPending += (p['total_amount'] ?? 0).toDouble();
    }

    // Units/Occupancy
    final units = await supabase
        .from('units')
        .select('id, is_occupied')
        .inFilter('property_id', propertyIds);

    int totalUnits = units.length;
    int occupiedUnits = units.where((u) => u['is_occupied'] == true).length;

    return {
      'totalTenants': tenants.length,
      'pendingApprovals': pendingApprovals.length,
      'pendingPayments': {
        'count': pendingPayments.length,
        'total': totalPending,
      },
      'occupancy': {
        'total': totalUnits,
        'occupied': occupiedUnits,
        'rate':
            totalUnits > 0 ? ((occupiedUnits / totalUnits) * 100).round() : 0,
      },
    };
  }

  // Get all properties owned by this user
  Future<List<Map<String, dynamic>>> getProperties() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    final properties = await supabase.from('properties').select('''
          *,
          units:units(id, is_occupied)
        ''').eq('owner_id', userId).order('created_at', ascending: false);

    return properties.map<Map<String, dynamic>>((prop) {
      final units = prop['units'] as List? ?? [];
      final totalUnits = units.length;
      final availableUnits =
          units.where((u) => u['is_occupied'] != true).length;
      return {
        ...prop,
        'total_units': totalUnits,
        'available_units': availableUnits,
      };
    }).toList();
  }

  // Get pending tenant approvals
  Future<List<Map<String, dynamic>>> getPendingApprovals() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    final properties =
        await supabase.from('properties').select('id').eq('owner_id', userId);

    final propertyIds = properties.map((p) => p['id']).toList();

    final response = await supabase
        .from('tenant_profiles')
        .select('''
          *,
          user_profiles:tenant_id(full_name, mobile_number, email),
          properties:property_id(property_name)
        ''')
        .inFilter('property_id', propertyIds)
        .eq('approval_status', 'pending')
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  // Approve or reject tenant
  Future<void> processTenantApproval({
    required String tenantProfileId,
    required bool approve,
  }) async {
    final status = approve ? 'approved' : 'rejected';

    await supabase
        .from('tenant_profiles')
        .update({'approval_status': status}).eq('id', tenantProfileId);

    // If approved, update unit occupancy
    if (approve) {
      final tenantProfile = await supabase
          .from('tenant_profiles')
          .select('room_number, property_id')
          .eq('id', tenantProfileId)
          .single();

      if (tenantProfile['room_number'] != null) {
        await supabase
            .from('units')
            .update({
              'is_occupied': true,
              'tenant_profile_id': tenantProfileId,
            })
            .eq('property_id', tenantProfile['property_id'])
            .eq('unit_number', tenantProfile['room_number']);
      }
    }
  }

  // Get pending payments
  Future<List<Map<String, dynamic>>> getPendingPayments() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    final properties =
        await supabase.from('properties').select('id').eq('owner_id', userId);

    final propertyIds = properties.map((p) => p['id']).toList();

    final response = await supabase
        .from('payments')
        .select('''
          *,
          tenant_profiles:tenant_profile_id(
            room_number,
            user_profiles:tenant_id(full_name, mobile_number)
          ),
          properties:property_id(property_name)
        ''')
        .inFilter('property_id', propertyIds)
        .eq('payment_status', 'pending')
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  // Approve or reject payment
  Future<void> processPayment({
    required String paymentId,
    required bool approve,
  }) async {
    final status = approve ? 'paid' : 'pending';

    await supabase.from('payments').update({
      'payment_status': status,
      if (approve) 'payment_date': DateTime.now().toIso8601String(),
    }).eq('id', paymentId);
  }

  // Get all tenants
  Future<List<Map<String, dynamic>>> getTenants() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    final properties =
        await supabase.from('properties').select('id').eq('owner_id', userId);

    final propertyIds = properties.map((p) => p['id']).toList();

    final response = await supabase
        .from('tenant_profiles')
        .select('''
          *,
          user_profiles:tenant_id(full_name, mobile_number, email),
          properties:property_id(property_name)
        ''')
        .inFilter('property_id', propertyIds)
        .eq('approval_status', 'approved')
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  // Get analytics
  Future<Map<String, dynamic>> getAnalytics() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    final properties =
        await supabase.from('properties').select('id').eq('owner_id', userId);

    final propertyIds = properties.map((p) => p['id']).toList();

    // Revenue by month
    final payments = await supabase
        .from('payments')
        .select('payment_month, total_amount, payment_status')
        .inFilter('property_id', propertyIds)
        .eq('payment_status', 'paid')
        .order('payment_month', ascending: false)
        .limit(12);

    Map<String, double> revenueByMonth = {};
    for (var p in payments) {
      final month = p['payment_month'].toString().substring(0, 7);
      revenueByMonth[month] =
          (revenueByMonth[month] ?? 0) + (p['total_amount'] ?? 0).toDouble();
    }

    // Payment methods
    final allPayments = await supabase
        .from('payments')
        .select('payment_method, total_amount')
        .inFilter('property_id', propertyIds)
        .eq('payment_status', 'paid');

    Map<String, double> methodTotals = {};
    for (var p in allPayments) {
      final method = p['payment_method'] ?? 'other';
      methodTotals[method] =
          (methodTotals[method] ?? 0) + (p['total_amount'] ?? 0).toDouble();
    }

    return {
      'revenue': revenueByMonth.entries
          .map((e) => {'month': e.key, 'total': e.value})
          .toList(),
      'paymentMethods': methodTotals.entries
          .map((e) => {'method': e.key, 'total': e.value})
          .toList(),
    };
  }

  // Send SMS notification
  Future<void> sendSmsNotification({
    required String recipientId,
    required String recipientMobile,
    required String message,
    required String notificationType,
  }) async {
    await supabase.from('sms_notifications').insert({
      'recipient_id': recipientId,
      'recipient_mobile': recipientMobile,
      'message': message,
      'notification_type': notificationType,
      'status': 'pending',
    });
  }

  // Block/Unblock tenant (updates is_approved in user_profiles)
  Future<void> blockTenant(String tenantId, bool block,
      {String? reason}) async {
    await supabase.from('user_profiles').update({
      'is_approved': !block,
    }).eq('id', tenantId);

    // Log the action in tenant_activities
    await supabase.from('tenant_activities').insert({
      'tenant_id': tenantId,
      'activity_type': block ? 'account_blocked' : 'account_unblocked',
      'activity_description':
          '${block ? 'Account blocked' : 'Account unblocked'}${reason != null ? ": $reason" : ""}',
    });
  }

  // Move tenant to another room (updates room_number in tenant_profiles and units)
  Future<void> moveTenantToRoom(String tenantProfileId, String newUnitId,
      {String? reason}) async {
    // Get current unit info
    final tenantProfile = await supabase
        .from('tenant_profiles')
        .select('id, property_id, room_number')
        .eq('id', tenantProfileId)
        .single();

    final oldRoomNumber = tenantProfile['room_number'];

    // Get new unit's number
    final newUnit = await supabase
        .from('units')
        .select('unit_number')
        .eq('id', newUnitId)
        .single();

    // Update tenant's room number
    await supabase.from('tenant_profiles').update({
      'room_number': newUnit['unit_number'],
    }).eq('id', tenantProfileId);

    // Update old unit to vacant (find by property_id and unit_number)
    if (oldRoomNumber != null) {
      await supabase
          .from('units')
          .update({
            'is_occupied': false,
            'tenant_profile_id': null,
          })
          .eq('property_id', tenantProfile['property_id'])
          .eq('unit_number', oldRoomNumber);
    }

    // Update new unit to occupied
    await supabase.from('units').update({
      'is_occupied': true,
      'tenant_profile_id': tenantProfileId,
    }).eq('id', newUnitId);

    // Log room transfer
    await supabase.from('tenant_activities').insert({
      'tenant_id': tenantProfile['id'],
      'activity_type': 'room_transfer',
      'activity_description':
          'Transferred from $oldRoomNumber to ${newUnit['unit_number']}${reason != null ? " - Reason: $reason" : ""}',
    });
  }

  // Create property
  Future<Map<String, dynamic>> createProperty({
    required String name,
    required String address,
    String? city,
    String? state,
    String? pincode,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    final response = await supabase
        .from('properties')
        .insert({
          'property_name': name,
          'property_address':
              '$address${city != null ? ', $city' : ''}${state != null ? ', $state' : ''}${pincode != null ? ' - $pincode' : ''}',
          'owner_id': userId,
          'status': 'active',
        })
        .select()
        .single();

    return response;
  }

  // Create floor
  Future<Map<String, dynamic>> createFloor({
    required String propertyId,
    required int floorNumber,
    String? name,
  }) async {
    final response = await supabase
        .from('floors')
        .insert({
          'property_id': propertyId,
          'floor_number': floorNumber,
          'floor_name': name ?? 'Floor $floorNumber',
        })
        .select()
        .single();

    return response;
  }

  // Create room/unit
  Future<Map<String, dynamic>> createRoom({
    required String propertyId,
    String? floorId,
    required String roomNumber,
    String unitType = 'single',
    int bedrooms = 1,
    int bathrooms = 1,
    required double rentAmount,
  }) async {
    final response = await supabase
        .from('units')
        .insert({
          'property_id': propertyId,
          'floor_id': floorId,
          'unit_number': roomNumber,
          'unit_type': unitType,
          'bedrooms': bedrooms,
          'bathrooms': bathrooms,
          'monthly_rent': rentAmount,
          'is_occupied': false,
        })
        .select()
        .single();

    return response;
  }

  // Get Unit Dashboard Summary
  Future<Map<String, dynamic>> getRoomDashboard(String unitId) async {
    // Get unit details
    final unit =
        await supabase.from('units').select('*').eq('id', unitId).single();

    // Get floor info if available
    Map<String, dynamic>? floorInfo;
    if (unit['floor_id'] != null) {
      floorInfo = await supabase
          .from('floors')
          .select('*')
          .eq('id', unit['floor_id'])
          .maybeSingle();
    }

    // Get active tenant if occupied
    Map<String, dynamic>? activeTenant;
    if (unit['tenant_profile_id'] != null) {
      final tenantProfile = await supabase
          .from('tenant_profiles')
          .select('*')
          .eq('id', unit['tenant_profile_id'])
          .maybeSingle();

      if (tenantProfile != null) {
        final userProfile = await supabase
            .from('user_profiles')
            .select('*')
            .eq('id', tenantProfile['tenant_id'])
            .maybeSingle();

        activeTenant = {
          ...tenantProfile,
          'user': userProfile,
        };
      }
    }

    return {
      'unit': {...unit, 'floor': floorInfo},
      'activeTenant': activeTenant,
    };
  }

  // Block/Unblock Unit (for maintenance)
  Future<void> blockRoom(String unitId, bool block, {String? reason}) async {
    await supabase.from('units').update({
      'is_occupied': block, // Use is_occupied to indicate maintenance
    }).eq('id', unitId);

    // Log the action
    await supabase.from('tenant_activities').insert({
      'tenant_id': supabase.auth.currentUser!.id,
      'activity_type': block ? 'unit_blocked' : 'unit_unblocked',
      'activity_description':
          'Unit ${block ? 'blocked for maintenance' : 'unblocked'}${reason != null ? ": $reason" : ""}',
    });
  }

  // Vacate Tenant (Update tenant profile with exit date)
  Future<void> vacateTenant({
    required String tenantProfileId,
    required DateTime exitDate,
    String? reason,
  }) async {
    final tenantProfile = await supabase
        .from('tenant_profiles')
        .select('*, tenant_id, property_id, room_number')
        .eq('id', tenantProfileId)
        .single();

    // Update lease_end_date to mark as vacated
    await supabase.from('tenant_profiles').update({
      'lease_end_date': exitDate.toIso8601String().split('T')[0],
      'approval_status': 'rejected', // Mark as inactive
    }).eq('id', tenantProfileId);

    // Update unit to vacant
    if (tenantProfile['room_number'] != null) {
      await supabase
          .from('units')
          .update({
            'is_occupied': false,
            'tenant_profile_id': null,
          })
          .eq('property_id', tenantProfile['property_id'])
          .eq('unit_number', tenantProfile['room_number']);
    }

    // Log the exit
    await supabase.from('tenant_activities').insert({
      'tenant_id': tenantProfile['tenant_id'],
      'activity_type': 'tenant_vacated',
      'activity_description':
          'Tenant vacated on ${exitDate.toString().split(' ')[0]}${reason != null ? " - Reason: $reason" : ""}',
    });
  }

  // Get all units for all properties
  Future<List<Map<String, dynamic>>> getAllRooms() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    // Get properties
    final properties = await supabase
        .from('properties')
        .select('id, property_name')
        .eq('owner_id', userId);

    if (properties.isEmpty) return [];

    final propertyIds = properties.map((p) => p['id']).toList();

    // Create property name map
    Map<String, String> propertyNames = {};
    for (var p in properties) {
      propertyNames[p['id']] = p['property_name'];
    }

    // Get all units for owner's properties
    final units = await supabase
        .from('units')
        .select('*')
        .inFilter('property_id', propertyIds)
        .order('unit_number');

    // Get floor names
    final floors = await supabase
        .from('floors')
        .select('id, floor_name')
        .inFilter('property_id', propertyIds);

    Map<String, String> floorNames = {};
    for (var f in floors) {
      floorNames[f['id']] = f['floor_name'];
    }

    // Enrich units with property and floor names
    List<Map<String, dynamic>> enrichedUnits = [];
    for (var unit in units) {
      enrichedUnits.add({
        ...unit,
        'property_name': propertyNames[unit['property_id']] ?? 'Unknown',
        'floor_name': unit['floor_id'] != null
            ? (floorNames[unit['floor_id']] ?? 'Unknown')
            : 'Ground Floor',
      });
    }

    // Sort by property, then unit number
    enrichedUnits.sort((a, b) {
      int cmp = a['property_name'].compareTo(b['property_name']);
      if (cmp != 0) return cmp;
      return a['unit_number'].compareTo(b['unit_number']);
    });

    return enrichedUnits;
  }

  // Get single property details
  Future<Map<String, dynamic>> getPropertyDetails(String propertyId) async {
    final property = await supabase
        .from('properties')
        .select('*, units:units(id, is_occupied)')
        .eq('id', propertyId)
        .single();

    final floors = await supabase
        .from('floors')
        .select('*')
        .eq('property_id', propertyId)
        .order('floor_number');

    return {
      ...property,
      'floors': floors,
    };
  }

  // Get floors for a specific property
  Future<List<Map<String, dynamic>>> getFloorsByProperty(
      String propertyId) async {
    final floors = await supabase
        .from('floors')
        .select('*')
        .eq('property_id', propertyId)
        .order('floor_number');
    return List<Map<String, dynamic>>.from(floors);
  }

  // Update rent for all units in a floor
  Future<void> updateFloorPricing(String floorId, double newRent) async {
    await supabase.from('units').update({
      'monthly_rent': newRent,
    }).eq('floor_id', floorId);
  }

  // Search for a user by phone number
  Future<Map<String, dynamic>?> searchUserByPhone(String phone) async {
    final response = await supabase
        .from('user_profiles')
        .select('*')
        .eq('mobile_number', phone)
        .maybeSingle();
    return response;
  }

  // Assign a user to a room manually
  Future<void> assignUserToRoom({
    required String userId,
    required String propertyId,
    required String roomId,
    required double rentAmount,
    required DateTime startDate,
    double? deposit,
  }) async {
    // 1. Create tenant profile
    final tenantProfile = await supabase
        .from('tenant_profiles')
        .insert({
          'tenant_id': userId,
          'property_id': propertyId,
          'monthly_rent': rentAmount,
          'security_deposit': deposit ?? 0,
          'move_in_date': startDate.toIso8601String(),
          'lease_start_date': startDate.toIso8601String(),
          'approval_status': 'approved',
        })
        .select()
        .single();

    // 2. Update unit to occupied
    await supabase.from('units').update({
      'is_occupied': true,
      'tenant_profile_id': tenantProfile['id'],
    }).eq('id', roomId);
  }

  // Update property details
  Future<void> updateProperty({
    required String id,
    required String name,
    required String address,
    String? city,
    String? state,
    String? pincode,
  }) async {
    await supabase.from('properties').update({
      'property_name': name,
      'property_address':
          '$address${city != null ? ', $city' : ''}${state != null ? ', $state' : ''}${pincode != null ? ' - $pincode' : ''}',
    }).eq('id', id);
  }

  // Update floor details
  Future<void> updateFloor({
    required String id,
    String? name,
    int? floorNumber,
  }) async {
    await supabase.from('floors').update({
      if (name != null) 'floor_name': name,
      if (floorNumber != null) 'floor_number': floorNumber,
    }).eq('id', id);
  }

  // Update room/unit details
  Future<void> updateRoom({
    required String id,
    String? roomNumber,
    String? unitType,
    int? bedrooms,
    double? rentAmount,
  }) async {
    await supabase.from('units').update({
      if (roomNumber != null) 'unit_number': roomNumber,
      if (unitType != null) 'unit_type': unitType,
      if (bedrooms != null) 'bedrooms': bedrooms,
      if (rentAmount != null) 'monthly_rent': rentAmount,
    }).eq('id', id);
  }
}
