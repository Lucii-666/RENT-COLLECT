import 'dart:convert';
import '../main.dart';

class TenantService {
  // Get tenant dashboard data
  Future<Map<String, dynamic>> getDashboardData() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    // Get tenant profile with property info
    final tenantProfileResponse = await supabase
        .from('tenant_profiles')
        .select('*')
        .eq('tenant_id', userId)
        .maybeSingle();

    if (tenantProfileResponse == null) {
      return {
        'tenantProfile': null,
        'recentPayments': [],
        'activities': [],
        'error': 'No tenant profile found. Please complete your registration.',
      };
    }

    // Get property details separately
    Map<String, dynamic>? propertyInfo;
    if (tenantProfileResponse['property_id'] != null) {
      propertyInfo = await supabase
          .from('properties')
          .select('property_name, property_address')
          .eq('id', tenantProfileResponse['property_id'])
          .maybeSingle();
    }

    final tenantProfile = {
      ...tenantProfileResponse,
      'properties': propertyInfo,
    };

    // Get recent payments
    final payments = await supabase
        .from('payments')
        .select()
        .eq('tenant_profile_id', tenantProfile['id'])
        .order('created_at', ascending: false)
        .limit(5);

    // Get activities
    final activities = await supabase
        .from('tenant_activities')
        .select()
        .eq('tenant_id', userId)
        .order('activity_date', ascending: false)
        .limit(10);

    return {
      'tenantProfile': tenantProfile,
      'recentPayments': payments,
      'activities': activities,
    };
  }

  // Submit rent payment
  Future<Map<String, dynamic>> submitPayment({
    required double rentAmount,
    required double electricityCharges,
    required double otherCharges,
    required DateTime paymentMonth,
    required String paymentMethod,
    String? transactionId,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    final tenantProfile = await supabase
        .from('tenant_profiles')
        .select('id, property_id')
        .eq('tenant_id', userId)
        .single();

    final totalAmount = rentAmount + electricityCharges + otherCharges;

    final response = await supabase
        .from('payments')
        .insert({
          'tenant_profile_id': tenantProfile['id'],
          'property_id': tenantProfile['property_id'],
          'payment_month': paymentMonth.toIso8601String().split('T')[0],
          'rent_amount': rentAmount,
          'electricity_charges': electricityCharges,
          'other_charges': otherCharges,
          'total_amount': totalAmount,
          'paid_amount': totalAmount,
          'payment_status': 'pending',
          'payment_method': paymentMethod,
          'transaction_id': transactionId,
        })
        .select()
        .single();

    // Log activity
    await _logActivity(
        'payment_submitted', 'Payment of ₹$totalAmount submitted');

    return response;
  }

  // Update electricity meter reading
  Future<void> updateElectricityReading(double reading) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    await supabase
        .from('tenant_profiles')
        .update({'electricity_meter_reading': reading}).eq('tenant_id', userId);

    await _logActivity(
        'meter_reading', 'Electricity meter reading updated: $reading');
  }

  // Get payment history
  Future<List<Map<String, dynamic>>> getPaymentHistory() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    final tenantProfile = await supabase
        .from('tenant_profiles')
        .select('id')
        .eq('tenant_id', userId)
        .single();

    final response = await supabase
        .from('payments')
        .select()
        .eq('tenant_profile_id', tenantProfile['id'])
        .order('payment_month', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  /// Get due rent periods (30-day cycles)
  Future<List<Map<String, dynamic>>> getDueRentPeriods() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    // 1. Get profile for lease_start_date and monthly_rent
    final profile = await getTenantProfile();
    final DateTime leaseStart = DateTime.parse(profile['lease_start_date']);
    final double monthlyRent = (profile['monthly_rent'] as num).toDouble();

    // 2. Get all payments (including pending)
    final payments = await getPaymentHistory();

    // 3. Calculate cycles from leaseStart to now + 30 days (to show next due)
    final now = DateTime.now();
    final List<Map<String, dynamic>> cycles = [];
    DateTime cycleStart = leaseStart;

    // Run until the cycle start is in the future
    while (cycleStart.isBefore(now.add(const Duration(days: 30)))) {
      final cycleEnd = cycleStart.add(const Duration(days: 29));
      final String periodLabel =
          '${_formatDate(cycleStart)} - ${_formatDate(cycleEnd)}';

      // Check if this cycle is paid
      final bool isPaid = payments.any((p) {
        final paymentMonth = DateTime.parse(p['payment_month']);
        return paymentMonth.year == cycleStart.year &&
            paymentMonth.month == cycleStart.month &&
            paymentMonth.day == cycleStart.day &&
            (p['payment_status'] == 'paid' || p['payment_status'] == 'pending');
      });

      if (!isPaid) {
        cycles.add({
          'start': cycleStart,
          'end': cycleEnd,
          'label': periodLabel,
          'amount': monthlyRent,
          'is_overdue': cycleEnd.isBefore(now),
          'days_remaining': cycleEnd.difference(now).inDays,
        });
      }

      cycleStart = cycleStart.add(const Duration(days: 30));
    }

    return cycles;
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}';
  }

  // Upload document
  Future<Map<String, dynamic>> uploadDocument({
    required String title,
    required String category,
    required String filePath,
    required String fileName,
    required int fileSize,
    required String fileType,
    String? notes,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    final tenantProfile = await supabase
        .from('tenant_profiles')
        .select('id, property_id')
        .eq('tenant_id', userId)
        .single();

    final response = await supabase
        .from('documents')
        .insert({
          'title': title,
          'category': category,
          'file_path': filePath,
          'file_name': fileName,
          'file_size': fileSize,
          'file_type': fileType,
          'uploaded_by': userId,
          'property_id': tenantProfile['property_id'],
          'tenant_id': userId,
          'status': 'tenant_uploaded',
          'notes': notes,
        })
        .select()
        .single();

    await _logActivity('document_uploaded', 'Document "$title" uploaded');

    return response;
  }

  // Get documents
  Future<List<Map<String, dynamic>>> getDocuments() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    final response = await supabase
        .from('documents')
        .select()
        .eq('tenant_id', userId)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  // Add roommate
  Future<Map<String, dynamic>> addRoommate({
    required String name,
    required String mobile,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    final tenantProfile = await supabase
        .from('tenant_profiles')
        .select('id')
        .eq('tenant_id', userId)
        .single();

    final response = await supabase
        .from('roommates')
        .insert({
          'tenant_profile_id': tenantProfile['id'],
          'roommate_name': name,
          'roommate_mobile': mobile,
        })
        .select()
        .single();

    await _logActivity('roommate_added', 'Roommate "$name" added');

    return response;
  }

  // Get roommates
  Future<List<Map<String, dynamic>>> getRoommates() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    final tenantProfile = await supabase
        .from('tenant_profiles')
        .select('id')
        .eq('tenant_id', userId)
        .single();

    final response = await supabase
        .from('roommates')
        .select()
        .eq('tenant_profile_id', tenantProfile['id']);

    return List<Map<String, dynamic>>.from(response);
  }

  // Get activities
  Future<List<Map<String, dynamic>>> getActivities() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    final response = await supabase
        .from('tenant_activities')
        .select()
        .eq('tenant_id', userId)
        .order('activity_date', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  // Mark activity as read
  Future<void> markActivityRead(String activityId) async {
    await supabase
        .from('tenant_activities')
        .update({'is_read': true}).eq('id', activityId);
  }

  // Helper to log activity
  Future<void> _logActivity(String type, String description) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    await supabase.from('tenant_activities').insert({
      'tenant_id': userId,
      'activity_type': type,
      'activity_description': description,
    });
  }

  // Submit maintenance request
  // Submit maintenance request (stored as an activity with details)
  Future<Map<String, dynamic>> submitMaintenanceRequest({
    required String title,
    required String description,
    required String category,
    required String priority,
    String? photoUrl,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    // Store as JSON string for easy parsing
    final Map<String, dynamic> requestData = {
      'title': title,
      'description': description,
      'category': category,
      'priority': priority,
      'photoUrl': photoUrl,
      'status': 'pending', // Initial status
    };

    final response = await supabase
        .from('tenant_activities')
        .insert({
          'tenant_id': userId,
          'activity_type': 'maintenance_request',
          'activity_description': jsonEncode(requestData),
        })
        .select()
        .single();

    return response;
  }

  // Get maintenance requests (from activities)
  Future<List<Map<String, dynamic>>> getMaintenanceRequests() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    final response = await supabase
        .from('tenant_activities')
        .select()
        .eq('tenant_id', userId)
        .eq('activity_type', 'maintenance_request')
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(response)
        .map((activity) {
          try {
            final data = jsonDecode(activity['activity_description']);
            return {
              ...activity,
              ...data,
              'status': data['status'] ?? 'pending',
              'date': activity['created_at'] != null
                  ? activity['created_at'].toString().split('T')[0]
                  : 'Unknown',
            };
          } catch (e) {
            return {
              ...activity,
              'title': 'Maintenance Request',
              'category': 'Other',
              'priority': 'Medium',
              'status': 'pending',
              'date': activity['created_at'] != null
                  ? activity['created_at'].toString().split('T')[0]
                  : 'Unknown',
            };
          }
        })
        .toList()
        .cast<Map<String, dynamic>>();
  }

  // Submit exit request (uses lease_end_date in tenant_profiles)
  Future<Map<String, dynamic>> submitExitRequest({
    required DateTime exitDate,
    String? reason,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    // Update lease_end_date to indicate exit
    final response = await supabase
        .from('tenant_profiles')
        .update({
          'lease_end_date': exitDate.toIso8601String().split('T')[0],
        })
        .eq('tenant_id', userId)
        .select()
        .single();

    // Log the exit request with reason
    await _logActivity('exit_request',
        'Exit request submitted for ${exitDate.toString().split(' ')[0]}${reason != null ? " - Reason: $reason" : ""}');

    return response;
  }

  // Get tenant profile for exit request screen
  Future<Map<String, dynamic>> getTenantProfile() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    final tenantProfile = await supabase
        .from('tenant_profiles')
        .select('*')
        .eq('tenant_id', userId)
        .maybeSingle();

    if (tenantProfile == null) {
      throw Exception('No tenant profile found');
    }

    // Get property details separately
    Map<String, dynamic>? propertyInfo;
    if (tenantProfile['property_id'] != null) {
      propertyInfo = await supabase
          .from('properties')
          .select('property_name, property_address')
          .eq('id', tenantProfile['property_id'])
          .maybeSingle();
    }

    return {
      ...tenantProfile,
      'properties': propertyInfo,
    };
  }

  // Upload credentials for tenant (stored as documents)
  Future<void> uploadCredentials({
    String? aadhaarNumber,
    String? aadhaarUrl,
    String? panNumber,
    String? panUrl,
    String? fatherName,
    String? parentPhone,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    final tenantProfile = await supabase
        .from('tenant_profiles')
        .select('id, property_id')
        .eq('tenant_id', userId)
        .maybeSingle();

    if (tenantProfile == null) {
      throw Exception('No tenant profile found');
    }

    // Store Aadhaar as document
    if (aadhaarNumber != null || aadhaarUrl != null) {
      await supabase.from('documents').insert({
        'title': 'Aadhaar Card',
        'category': 'id_proof',
        'file_path': aadhaarUrl ?? '',
        'file_name': 'Aadhaar_$aadhaarNumber.jpg',
        'file_size': 0,
        'file_type': 'image/jpeg',
        'uploaded_by': userId,
        'property_id': tenantProfile['property_id'],
        'tenant_id': userId,
        'notes':
            'Aadhaar Number: $aadhaarNumber${fatherName != null ? ', Father: $fatherName' : ''}${parentPhone != null ? ', Parent Phone: $parentPhone' : ''}',
      });
    }

    // Store PAN as document
    if (panNumber != null || panUrl != null) {
      await supabase.from('documents').insert({
        'title': 'PAN Card',
        'category': 'id_proof',
        'file_path': panUrl ?? '',
        'file_name': 'PAN_$panNumber.jpg',
        'file_size': 0,
        'file_type': 'image/jpeg',
        'uploaded_by': userId,
        'property_id': tenantProfile['property_id'],
        'tenant_id': userId,
        'notes': 'PAN Number: $panNumber',
      });
    }

    await _logActivity('credentials_uploaded', 'Tenant credentials updated');
  }

  // ─── Notifications ───

  /// Get unread notification count for current user
  Future<int> getUnreadNotificationCount() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return 0;

    try {
      final response = await supabase
          .from('notifications')
          .select('id')
          .eq('user_id', userId)
          .eq('is_read', false);

      return response.length;
    } catch (e) {
      return 0;
    }
  }

  /// Check if rent is due and create a notification (call on dashboard load)
  Future<void> checkAndCreateRentDueNotification() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final profile = await supabase
          .from('tenant_profiles')
          .select('id, monthly_rent, move_in_date, lease_start_date, approval_status')
          .eq('tenant_id', userId)
          .maybeSingle();

      if (profile == null || profile['approval_status'] != 'approved') return;

      final now = DateTime.now();
      final rent = (profile['monthly_rent'] as num?)?.toDouble() ?? 0;

      // Check if there's already a rent-due notification this month
      final existing = await supabase
          .from('notifications')
          .select('id')
          .eq('user_id', userId)
          .eq('type', 'payment')
          .gte('created_at', DateTime(now.year, now.month, 1).toIso8601String())
          .limit(1);

      if (existing.isNotEmpty) return; // Already notified this month

      // Create rent due notification on/after the 25th
      if (now.day >= 25) {
        await supabase.from('notifications').insert({
          'user_id': userId,
          'type': 'payment',
          'title': 'Rent Due',
          'message': 'Your rent of ₹${rent.toStringAsFixed(0)} is due. Please pay before the end of the cycle.',
          'is_read': false,
        });
      }
    } catch (e) {
      // Silently fail — notification is not critical
    }
  }

  /// Create a notification for the property owner when tenant submits maintenance
  Future<void> createMaintenanceNotificationForOwner({
    required String title,
    required String propertyId,
  }) async {
    try {
      final property = await supabase
          .from('properties')
          .select('owner_id, property_name')
          .eq('id', propertyId)
          .maybeSingle();

      if (property == null) return;

      final userId = supabase.auth.currentUser?.id;
      final userProfile = await supabase
          .from('user_profiles')
          .select('full_name')
          .eq('id', userId!)
          .maybeSingle();

      final tenantName = userProfile?['full_name'] ?? 'A tenant';

      await supabase.from('notifications').insert({
        'user_id': property['owner_id'],
        'type': 'maintenance',
        'title': 'Maintenance Request',
        'message': '$tenantName reported: $title at ${property['property_name']}',
        'is_read': false,
      });
    } catch (e) {
      // Silently fail
    }
  }
}
