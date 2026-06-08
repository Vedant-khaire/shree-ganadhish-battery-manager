import 'package:intl/intl.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import '../models/reminder.dart';

class FormatUtils {
  /// Formats a double amount into the Indian Rupee numbering system (e.g., ₹12,500).
  /// Shows 2 decimal points only if there is a fractional value, otherwise none.
  static String formatIndianCurrency(double amount) {
    final hasDecimal = amount % 1 != 0;
    final formatter = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: hasDecimal ? 2 : 0,
    );
    return formatter.format(amount);
  }

  /// Formats a date string (YYYY-MM-DD) into a more readable format (e.g., 26 May 2026).
  static String formatDate(String dateStr) {
    if (dateStr.isEmpty) return '';
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('dd MMM yyyy').format(date);
    } catch (_) {
      return dateStr;
    }
  }

  /// Groups and sorts a list of reminders using the chronological business rules:
  /// 1. Overdue Udhari (weight 1)
  /// 2. Due Today Udhari (weight 2)
  /// 3. Overdue General (weight 3)
  /// 4. Due Today General (weight 4)
  /// 5. Upcoming (weight 5)
  /// 6. Completed (weight 6)
  /// Within each group, items are sorted by reminderDate ascending.
  static void sortReminders(List<Reminder> reminders) {
    int getSortWeight(Reminder r) {
      if (r.isCompleted) {
        return 6;
      }
      final isUdhari = r.reminderType == 'UDHARI' || r.reminderType == 'UDHARI_RECOVERY' || r.reminderCategory == 'UDHARI';
      if (isUdhari) {
        if (r.reminderStatus == 'OVERDUE' || r.reminderStatus == 'EXPIRED') {
          return 1;
        } else if (r.reminderStatus == 'DUE') {
          return 2;
        } else {
          return 5;
        }
      } else {
        if (r.reminderStatus == 'OVERDUE' || r.reminderStatus == 'EXPIRED') {
          return 3;
        } else if (r.reminderStatus == 'DUE') {
          return 4;
        } else {
          return 5;
        }
      }
    }

    reminders.sort((a, b) {
      final wA = getSortWeight(a);
      final wB = getSortWeight(b);
      if (wA != wB) {
        return wA.compareTo(wB);
      }
      return a.reminderDate.compareTo(b.reminderDate);
    });
  }
}

class ErrorParser {
  /// Parses any thrown error/exception into a user-friendly readable message.
  static String parse(dynamic error) {
    if (error is DioException) {
      if (error.message != null &&
          (error.message!.contains('Server is starting') ||
           error.message!.contains('waking up') ||
           error.message!.contains('Please wait'))) {
        return error.message!;
      }
      
      final errorStr = error.toString().toLowerCase();
      final errorObjStr = error.error?.toString().toLowerCase() ?? '';

      final isTimeout = error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          errorStr.contains('timeout') ||
          errorObjStr.contains('timeout');

      final isConnection = error.type == DioExceptionType.connectionError ||
          errorStr.contains('socketexception') ||
          errorObjStr.contains('socketexception') ||
          errorObjStr.contains('xmlhttprequest') ||
          errorObjStr.contains('networkerror');

      if (isTimeout) {
        return 'Server is starting. This may take up to 60 seconds because the backend is waking up. Please wait...';
      }
      
      if (isConnection) {
        if (errorObjStr.contains('networkerror') || errorStr.contains('networkerror') || errorStr.contains('failed to host lookup')) {
          return 'Internet connection is offline. Please check your network.';
        }
        return 'Server is starting. This may take up to 60 seconds because the backend is waking up. Please wait...';
      }
      
      switch (error.type) {
        case DioExceptionType.badResponse:
          final response = error.response;
          if (response != null) {
            final statusCode = response.statusCode;
            if (statusCode == 401) {
              return 'Session expired. Please log in again.';
            }
            if (statusCode != null && statusCode >= 500) {
              return 'Internal server error (HTTP $statusCode). Please contact support.';
            }
            
            var data = response.data;
            if (data is List<int>) {
              try {
                final decoded = utf8.decode(data);
                data = jsonDecode(decoded);
              } catch (_) {}
            }
            
            if (data is Map<String, dynamic>) {
              final detail = data['detail'];
              if (detail != null) {
                if (detail is String) {
                  return detail;
                } else if (detail is List) {
                  // Parse FastAPI validation errors
                  final messages = detail.map((item) {
                    if (item is Map && item.containsKey('msg')) {
                      final loc = item['loc'] as List?;
                      final fieldName = (loc != null && loc.length > 1) ? loc.last : null;
                      final msg = item['msg'].toString();
                      return fieldName != null ? '${fieldName.toString().toUpperCase()}: $msg' : msg;
                    }
                    return item.toString();
                  }).join('\n');
                  return messages;
                }
                return detail.toString();
              }
            }
            return 'Request failed with status code: $statusCode';
          }
          return 'Received invalid response from server.';
        default:
          return 'Network request failed. Please try again.';
      }
    }
    return error.toString().replaceAll('Exception:', '').trim();
  }
}

class AppLogger {
  static void log(String message) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[AUDIT LOG] ${DateTime.now().toIso8601String()}: $message');
    }
  }
}
