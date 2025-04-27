import 'dart:convert';

import 'utils/logger.dart';

const String API_HOST = "https://YOUR_API_HOST.com/api/v1";
List<String> facilityList = [
  "Nursing Home",
  "Assisted Living",
  "Independent Living",
  "Memory Care",
  "Skilled Nursing Facility",
  "Continuing Care Retirement Community",
  "Adult Day Care",
  "Respite Care",
  "Palliative Care",
  "Hospice Care",
  "Home Health Care",
  "Rehabilitation Facility",
  "Long-Term Acute Care Hospital",
  "Subacute Rehabilitation Facility",
];
List<String> categoryList = [
  "General",
  "Urgent",
  "Emergency",
  "Routine",
  "Follow-up",
  "Preventive",
  "Diagnostic",
  "Therapeutic",
  "Surgical",
  "Rehabilitative",
  "Palliative",
  "End-of-life",
];

Future<void> fetchConfig(dio) async {
  
  try {
    final facilityResponse = await dio.get('$API_HOST/auth/settings/facility_options');
    if (facilityResponse.statusCode == 200) {
      facilityList = List<String>.from(jsonDecode(facilityResponse.data)['data']['facility']);
    }
  } catch (e) {
    appLogger.e('Failed to fetch facility options: $e');
  }

  try {
    final categoryResponse = await dio.get('$API_HOST/auth/settings/category_options');
    if (categoryResponse.statusCode == 200) {
      categoryList = List<String>.from(jsonDecode(categoryResponse.data)['data']['category']);
    }
  } catch (e) {
    appLogger.e('Failed to fetch category options: $e');
  }
}
