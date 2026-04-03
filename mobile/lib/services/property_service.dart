import '../main.dart';

class PropertyService {
  // Get all properties for selection
  Future<List<Map<String, dynamic>>> getProperties() async {
    final response = await supabase
        .from('properties')
        .select('id, property_name, property_address, available_units, status')
        .eq('status', 'active')
        .gt('available_units', 0)
        .order('property_name');

    return List<Map<String, dynamic>>.from(response);
  }

  // Get floors for a property
  Future<List<Map<String, dynamic>>> getFloors(String propertyId) async {
    final response = await supabase
        .from('floors')
        .select('id, floor_number, floor_name, total_units')
        .eq('property_id', propertyId)
        .order('floor_number');

    return List<Map<String, dynamic>>.from(response);
  }

  // Get available units for a floor
  Future<List<Map<String, dynamic>>> getAvailableUnits(String floorId) async {
    final response = await supabase
        .from('units')
        .select('id, unit_number, unit_type, bedrooms, bathrooms, monthly_rent, square_feet')
        .eq('floor_id', floorId)
        .eq('is_occupied', false)
        .order('unit_number');

    return List<Map<String, dynamic>>.from(response);
  }

  // Get property details
  Future<Map<String, dynamic>> getPropertyDetails(String propertyId) async {
    final response = await supabase
        .from('properties')
        .select('''
          *,
          floors(id, floor_number, floor_name, total_units),
          units(id, unit_number, is_occupied)
        ''')
        .eq('id', propertyId)
        .single();

    return response;
  }

  // Create property (owner only)
  Future<Map<String, dynamic>> createProperty({
    required String propertyName,
    required String propertyAddress,
    int totalUnits = 1,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    final response = await supabase.from('properties').insert({
      'owner_id': userId,
      'property_name': propertyName,
      'property_address': propertyAddress,
      'total_units': totalUnits,
      'available_units': totalUnits,
      'status': 'active',
    }).select().single();

    return response;
  }

  // Create floor
  Future<Map<String, dynamic>> createFloor({
    required String propertyId,
    required int floorNumber,
    required String floorName,
  }) async {
    final response = await supabase.from('floors').insert({
      'property_id': propertyId,
      'floor_number': floorNumber,
      'floor_name': floorName,
      'total_units': 0,
    }).select().single();

    return response;
  }

  // Create unit
  Future<Map<String, dynamic>> createUnit({
    required String propertyId,
    required String floorId,
    required String unitNumber,
    String? unitType,
    int bedrooms = 1,
    int bathrooms = 1,
    double? squareFeet,
    double? monthlyRent,
  }) async {
    final response = await supabase.from('units').insert({
      'property_id': propertyId,
      'floor_id': floorId,
      'unit_number': unitNumber,
      'unit_type': unitType,
      'bedrooms': bedrooms,
      'bathrooms': bathrooms,
      'square_feet': squareFeet,
      'monthly_rent': monthlyRent,
      'is_occupied': false,
    }).select().single();

    // Update floor unit count
    await supabase.rpc('increment_floor_units', params: {'floor_id': floorId});

    return response;
  }

  // Update property
  Future<void> updateProperty({
    required String propertyId,
    String? propertyName,
    String? propertyAddress,
    String? status,
  }) async {
    final updates = <String, dynamic>{};
    if (propertyName != null) updates['property_name'] = propertyName;
    if (propertyAddress != null) updates['property_address'] = propertyAddress;
    if (status != null) updates['status'] = status;

    if (updates.isNotEmpty) {
      await supabase
          .from('properties')
          .update(updates)
          .eq('id', propertyId);
    }
  }

  // Delete unit
  Future<void> deleteUnit(String unitId) async {
    final unit = await supabase
        .from('units')
        .select('floor_id, is_occupied')
        .eq('id', unitId)
        .single();

    if (unit['is_occupied'] == true) {
      throw Exception('Cannot delete occupied unit');
    }

    await supabase.from('units').delete().eq('id', unitId);
  }

  // Get property statistics
  Future<Map<String, dynamic>> getPropertyStats(String propertyId) async {
    final units = await supabase
        .from('units')
        .select('id, is_occupied, monthly_rent')
        .eq('property_id', propertyId);

    int totalUnits = units.length;
    int occupiedUnits = units.where((u) => u['is_occupied'] == true).length;
    double totalRent = 0;
    for (var u in units.where((u) => u['is_occupied'] == true)) {
      totalRent += (u['monthly_rent'] as num?)?.toDouble() ?? 0;
    }

    return {
      'totalUnits': totalUnits,
      'occupiedUnits': occupiedUnits,
      'vacantUnits': totalUnits - occupiedUnits,
      'occupancyRate': totalUnits > 0 ? ((occupiedUnits / totalUnits) * 100).round() : 0,
      'monthlyRentIncome': totalRent,
    };
  }
}
