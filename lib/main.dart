import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Entry point of the app
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize background processing
  await _initializeBackgroundTasks();
  
  runApp(const ActivityCountdownApp());
}

/// Initialize background task processing
Future<void> _initializeBackgroundTasks() async {
  // Initialize local notifications
  await _initializeNotifications();
}

/// Initialize local notifications
Future<void> _initializeNotifications() async {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);
}



///
/// Root widget for the app
///
class ActivityCountdownApp extends StatelessWidget {
  const ActivityCountdownApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Activity Countdown',
      // --- App-wide theme configuration ---
      theme: ThemeData(
        primarySwatch: Colors.grey,
        useMaterial3: true,
        colorScheme: const ColorScheme.dark(
          primary: Colors.white,
          secondary: Colors.grey,
          surface: Colors.black,
          background: Colors.black,
          onPrimary: Colors.black,
          onSecondary: Colors.white,
          onSurface: Colors.white,
          onBackground: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: Colors.grey[900],
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 4,
        ),
        scaffoldBackgroundColor: Colors.black,
        dialogTheme: DialogThemeData(
          backgroundColor: Colors.grey[900],
          titleTextStyle: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
          contentTextStyle: const TextStyle(
            color: Colors.white70,
            fontSize: 16,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          labelStyle: TextStyle(color: Colors.grey[400]),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey[600]!),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.white, width: 2),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey[600]!),
          ),
        ),
      ),
      // --- Main screen of the app ---
      home: const HomeScreen(),
    );
  }
}

///
/// HomeScreen: Main screen showing the list of activities and controls
///
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

///
/// State for HomeScreen
///
class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  // --- List of all activities ---
  List<Activity> activities = [];

  // --- Timer for countdown updates ---
  Timer? _timer;

  // --- Last date when timers were checked/reset ---
  String? _lastDate;

  // --- Platform channel for notifications ---
  static const platform = MethodChannel('activity_countdown/notifications');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadActivities();      // Load activities from storage
    _checkDateChange();     // Check if date has changed for daily reset
    _startTimer();          // Start the countdown timer
    _setupNotifications();  // Set up notification channel/permissions
    
    // Request battery optimization exemption
    _requestBatteryOptimizationExemption();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        // Save activities when app goes to background
        _saveActivities();
        break;
      case AppLifecycleState.resumed:
        // Reload activities when app comes back to foreground
        _loadActivities();
        break;
      default:
        break;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // --- Notification setup and permissions ---
  Future<void> _setupNotifications() async {
    try {
      await platform.invokeMethod('createNotificationChannel');
      // Request notification permission on Android 13+
      await _requestNotificationPermission();
    } catch (e) {
      // Ignore if notifications can't be set up
    }
  }

  Future<void> _requestNotificationPermission() async {
    try {
      await platform.invokeMethod('requestNotificationPermission');
    } catch (e) {
      // Permission request failed, will use fallback
    }
  }

  Future<void> _requestBatteryOptimizationExemption() async {
    try {
      await platform.invokeMethod('requestBatteryOptimizationExemption');
    } catch (e) {
      // Battery optimization request failed, will use fallback
    }
  }

  // --- Start the periodic timer to update countdowns ---
  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        for (int i = 0; i < activities.length; i++) {
          if (activities[i].isRunning && activities[i].remainingTime > 0) {
            activities[i].remainingTime--;

            // Update persistent notification every second
            _updateTimerNotification(activities[i]);

            // Show notification when time is up
            if (activities[i].remainingTime == 0) {
              activities[i].isRunning = false;
              _cancelTimerNotification(activities[i]); // Remove persistent notification
              _showNotification(activities[i].name);
            }
          }
        }
        _saveActivities();
      });
    });
  }

  // --- Check if the date has changed and reset timers if needed ---
  void _checkDateChange() {
    final currentDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
    if (_lastDate != null && _lastDate != currentDate) {
      _resetDailyTimers();
    }
    _lastDate = currentDate;
  }

  // --- Reset all activity timers for a new day ---
  void _resetDailyTimers() {
    setState(() {
      for (var activity in activities) {
        activity.remainingTime = activity.dailyLimit; // Reset to daily limit in seconds
        activity.isRunning = false;
        activity.isPaused = false;
      }
      _cancelAllTimerNotifications(); // Clear all notifications
      _saveActivities();
    });
  }

  // --- Load activities and last date from persistent storage ---
  Future<void> _loadActivities() async {
    final prefs = await SharedPreferences.getInstance();
    final activitiesJson = prefs.getStringList('activities') ?? [];
    final lastDate = prefs.getString('lastDate');

    setState(() {
      activities = activitiesJson
          .map((json) => Activity.fromJson(jsonDecode(json)))
          .toList();
      _lastDate = lastDate;
    });

    _checkDateChange();
  }

  // --- Save activities and last date to persistent storage ---
  Future<void> _saveActivities() async {
    final prefs = await SharedPreferences.getInstance();
    final activitiesJson = activities
        .map((activity) => jsonEncode(activity.toJson()))
        .toList();
    await prefs.setStringList('activities', activitiesJson);
    await prefs.setString('lastDate', _lastDate ?? '');
  }

  // --- Show a notification (native or fallback in-app) when time is up ---
  Future<void> _showNotification(String activityName) async {
    try {
      // Try to show native notification
      await platform.invokeMethod('showNotification', {
        'id': activities.indexWhere((a) => a.name == activityName),
        'title': '⏰ $activityName time is up!',
        'body': 'Daily time limit reached: $activityName.',
      });
    } catch (e) {
      // Fallback: show a prominent in-app alert
      if (mounted) {
        _showTimeUpAlert(activityName);
      }
    }
  }

  // --- Show persistent timer notification ---
  Future<void> _showTimerNotification(Activity activity) async {
    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    final AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'timer_channel',
      'Timer Notifications',
      channelDescription: 'Shows ongoing timer status',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      showWhen: false,
    );

    final NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    final String timeLeft = _formatTime(activity.remainingTime);
    
    // Use a fixed ID (1) to ensure only one notification exists at a time
    await flutterLocalNotificationsPlugin.show(
      1, // Fixed ID for single notification
      '⏰ ${activity.name}',
      'Time remaining: $timeLeft',
      platformChannelSpecifics,
    );
  }

  // --- Update timer notification ---
  Future<void> _updateTimerNotification(Activity activity) async {
    if (activity.isRunning && activity.remainingTime > 0) {
      await _showTimerNotification(activity);
    } else {
      await _cancelTimerNotification(activity);
    }
  }

  // --- Cancel timer notification ---
  Future<void> _cancelTimerNotification(Activity activity) async {
    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();
    
    // Cancel the fixed notification ID
    await flutterLocalNotificationsPlugin.cancel(1);
  }

  // --- Cancel all timer notifications ---
  Future<void> _cancelAllTimerNotifications() async {
    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();
    
    // Cancel the fixed notification ID
    await flutterLocalNotificationsPlugin.cancel(1);
  }

  // --- Check if any activity is running and manage notifications ---
  void _manageNotifications() {
    // Find the currently running activity
    final runningActivity = activities.firstWhere(
      (activity) => activity.isRunning,
      orElse: () => Activity(name: '', dailyLimit: 0, remainingTime: 0),
    );

    if (runningActivity.name.isNotEmpty) {
      // Show notification for running activity
      _showTimerNotification(runningActivity);
    } else {
      // Cancel all notifications if no activity is running
      _cancelAllTimerNotifications();
    }
  }

  // --- Format time as HH:MM:SS ---
  String _formatTime(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    if (totalSeconds == 0) return '00:00:00';
    
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  // --- Show an in-app dialog when time is up ---
  void _showTimeUpAlert(String activityName) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text(
          '⏰ $activityName Time is Up!',
          style: const TextStyle(color: Colors.white, fontSize: 20),
        ),
        content: Text(
          'Your daily time limit for $activityName has been reached.',
          style: const TextStyle(color: Colors.white70, fontSize: 16),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // --- Show dialog to add a new activity ---
  void _addActivity() {
    showDialog(
      context: context,
      builder: (context) => const AddActivityDialog(),
    ).then((newActivity) {
      if (newActivity != null) {
        setState(() {
          activities.add(newActivity);
        });
        _saveActivities();
      }
    });
  }

  // --- Start, pause, or resume an activity timer ---
  void _toggleActivity(Activity activity) {
    setState(() {
      if (activity.isRunning) {
        // Pause the current activity
        activity.isRunning = false;
        activity.isPaused = true;
      } else if (activity.isPaused) {
        // Resume the paused activity
        activity.isRunning = true;
        activity.isPaused = false;
      } else {
        // Start a new activity (stop all others first)
        for (var a in activities) {
          a.isRunning = false;
          a.isPaused = false;
        }
        // Start this activity
        activity.isRunning = true;
        activity.isPaused = false;
      }
    });
    
    // Manage notifications after state changes
    _manageNotifications();
    _saveActivities();
  }

  // --- Delete an activity from the list ---
  void _deleteActivity(Activity activity) {
    setState(() {
      // Cancel notification if this activity was running
      if (activity.isRunning || activity.isPaused) {
        _cancelTimerNotification(activity);
      }
      activities.remove(activity);
    });
    _saveActivities();
  }

  // --- Build the main UI for the HomeScreen ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset(
              'logo.png',
              height: 32,
              width: 32,
            ),
            const SizedBox(width: 12),
            Text(
              'Activity Countdown',
              style: TextStyle(
                fontSize: 20, // Reduced from 20
              ),
            ),
          ],
        ),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          if (activities.isNotEmpty)
            IconButton(
              onPressed: _resetDailyTimers,
              icon: const Icon(Icons.refresh),
              tooltip: 'Reset All Timers',
            ),
        ],
      ),
      body: activities.isEmpty
          // --- Show empty state if no activities ---
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'logo.png',
                    height: 80,
                    width: 80,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No activities yet.\nTap + to add your first activity!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18, // Reduced from 18
                      color: Colors.grey[400],
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            )
          // --- Show list of activities ---
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: activities.length,
              itemBuilder: (context, index) {
                final activity = activities[index];
                return ActivityCard(
                  activity: activity,
                  onToggle: () => _toggleActivity(activity),
                  onDelete: () => _deleteActivity(activity),
                  onReset: () => _resetSingleTimer(activity),
                );
              },
            ),
      // --- Floating action button to add new activity ---
      floatingActionButton: FloatingActionButton(
        onPressed: _addActivity,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        child: const Icon(Icons.add),
      ),
    );
  }

  // --- Reset a single activity's timer and show a snackbar ---
  void _resetSingleTimer(Activity activity) {
    setState(() {
      activity.remainingTime = activity.dailyLimit; // Reset to daily limit in seconds
      activity.isRunning = false;
      activity.isPaused = false;
      _cancelTimerNotification(activity); // Clear notification
      _saveActivities();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${activity.name} timer has been reset!'),
        backgroundColor: Colors.grey[800],
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

///
/// ActivityCard: Widget for displaying a single activity in the list
///
class ActivityCard extends StatelessWidget {
  final Activity activity;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final VoidCallback onReset;

  const ActivityCard({
    super.key,
    required this.activity,
    required this.onToggle,
    required this.onDelete,
    required this.onReset,
  });

  // --- Format seconds as HH:MM:SS ---
  String _formatTime(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    // Always show HH:MM:SS format for consistency
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isActive = activity.isRunning || activity.isPaused;
    final isRunning = activity.isRunning;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        // --- Activity name ---
        title: Text(
          activity.name,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 12,
            color: isActive ? Colors.white : Colors.white70,
          ),
        ),
        // --- Remaining time ---
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${_formatTime(activity.remainingTime)}',
            style: TextStyle(
              fontSize: 12,
              color: activity.remainingTime < 30 ? Colors.white : Colors.grey[400], // 30 seconds warning
              fontWeight: activity.remainingTime < 30 ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
        // --- Action buttons: Start/Pause, Reset, Delete ---
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Start/Pause button
            ElevatedButton(
              onPressed: activity.remainingTime > 0 ? onToggle : null, // Disable when time is 0
              style: ElevatedButton.styleFrom(
                backgroundColor: isRunning 
                    ? Colors.grey[600] 
                    : (activity.remainingTime > 0 ? Colors.white : Colors.grey[400]),
                foregroundColor: isRunning 
                    ? Colors.white 
                    : (activity.remainingTime > 0 ? Colors.black : Colors.grey[600]),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12, // Increased from 10 to 12
                ),
                minimumSize: const Size(90, 40), // Increased width from 80 to 90
                fixedSize: const Size(90, 40), // Increased width from 80 to 90
              ),
              child: Text(
                isRunning 
                    ? 'Pause' 
                    : (activity.remainingTime > 0 ? 'Start' : 'Done'),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Reset button
            IconButton(
              onPressed: onReset,
              icon: Icon(
                Icons.refresh,
                color: Colors.grey[400],
                size: 18,
              ),
              style: IconButton.styleFrom(
                backgroundColor: Colors.grey[800],
                padding: EdgeInsets.all(8),
                minimumSize: Size(
                  20,
                  20,
                ),
              ),
              tooltip: 'Reset Timer',
            ),
            const SizedBox(width: 4),
            // Delete button
            IconButton(
              onPressed: onDelete,
              icon: Icon(
                Icons.delete_outline,
                color: Colors.grey[400],
                size: 18,
              ),
              style: IconButton.styleFrom(
                backgroundColor: Colors.grey[800],
                padding: EdgeInsets.all(8),
                minimumSize: Size(
                  20,
                  20,
                ),
              ),
              tooltip: 'Delete Activity',
            ),
          ],
        ),
      ),
    );
  }
}

///
/// AddActivityDialog: Dialog for adding a new activity
///
class AddActivityDialog extends StatefulWidget {
  const AddActivityDialog({super.key});

  @override
  State<AddActivityDialog> createState() => _AddActivityDialogState();
}

///
/// State for AddActivityDialog
///
class _AddActivityDialogState extends State<AddActivityDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  int _hours = 0;
  int _minutes = 0;
  bool _showTimeError = false; // Track when to show time validation error
  bool _showNameError = false; // Track when to show name validation error

  @override
  void initState() {
    super.initState();
    // Add listener to update character counter and hide error in real-time
    _nameController.addListener(() {
      setState(() {
        // Hide name error when user starts typing
        if (_nameController.text.isNotEmpty && _showNameError) {
          _showNameError = false;
        }
        // This will rebuild the widget to update the character counter
      });
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _validateTime() {
    setState(() {
      _showTimeError = (_hours == 0 && _minutes == 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add New Activity'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
                        // --- Activity name input ---
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Activity Name',
                border: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: _showNameError ? Colors.red[400]! : Colors.grey[600]!,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: _showNameError ? Colors.red[400]! : Colors.grey[600]!,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: _showNameError ? Colors.red[400]! : Colors.white,
                    width: 2,
                  ),
                ),
                counterText: '', // Hide default counter
              ),
              maxLength: 20, // Limit to 20 characters
              style: TextStyle(
                fontSize: 14, // Reduced from 14
              ),
              onChanged: (value) {
                // Hide error when user starts typing
                if (value.isNotEmpty && _showNameError) {
                  setState(() {
                    _showNameError = false;
                  });
                }
              },
            ),
            // --- Show name validation error below the input ---
            if (_showNameError)
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 8),
                child: Text(
                  'Please enter an activity name',
                  style: TextStyle(
                    color: Colors.red[400],
                    fontSize: 12,
                  ),
                ),
              ),
            // --- Custom character counter ---
            Padding(
              padding: const EdgeInsets.only(top: 8, right: 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${_nameController.text.length}/20',
                  style: TextStyle(
                    fontSize: 12,
                    color: _nameController.text.length > 18 ? Colors.orange : Colors.grey[600],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // --- Time limit pickers (hours and minutes) ---
            Row(
              children: [
                // Hours dropdown
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _hours,
                    decoration: InputDecoration(
                      labelText: 'Hours',
                      border: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: _showTimeError ? Colors.red : Colors.grey[600]!,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: _showTimeError ? Colors.red : Colors.grey[600]!,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: _showTimeError ? Colors.red : Colors.white,
                        ),
                      ),
                    ),
                    style: TextStyle(
                      fontSize: 14, // Reduced from 14
                    ),
                    items: List.generate(24, (index) => index) // 0-23 hours (24 items total)
                        .map((hour) => DropdownMenuItem(
                              value: hour,
                              child: Text(
                                '$hour',
                                style: TextStyle(
                                  fontSize: 14, // Reduced from 14
                                ),
                              ),
                            ))
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _hours = value ?? 0;
                        _validateTime();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 16),
                // Minutes dropdown
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _minutes,
                    decoration: InputDecoration(
                      labelText: 'Minutes',
                      border: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: _showTimeError ? Colors.red : Colors.grey[600]!,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: _showTimeError ? Colors.red : Colors.grey[600]!,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: _showTimeError ? Colors.red : Colors.white,
                        ),
                      ),
                    ),
                    style: TextStyle(
                      fontSize: 14, // Reduced from 14
                    ),
                    items: List.generate(60, (index) => index)
                        .map((minute) => DropdownMenuItem(
                              value: minute,
                              child: Text(
                                '$minute',
                                style: TextStyle(
                                  fontSize: 14, // Reduced from 14
                                ),
                              ),
                            ))
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _minutes = value ?? 0;
                        _validateTime();
                      });
                    },
                  ),
                ),
              ],
            ),
            // --- Show time validation error below the inputs ---
            if (_showTimeError)
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 8),
                child: Text(
                  'Please set a time limit greater than 0',
                  style: TextStyle(
                    color: Colors.red[400],
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
      // --- Dialog action buttons ---
      actions: [
        // Cancel button
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Cancel',
            style: TextStyle(
              fontSize: 14, // Reduced from 14
            ),
          ),
        ),
        // Add button
        ElevatedButton(
          onPressed: () {
            // Trigger validation when Add button is clicked
            _validateTime();
            
            // Check name validation
            if (_nameController.text.trim().isEmpty) {
              setState(() {
                _showNameError = true;
              });
              return;
            }
            
            if (_hours > 0 || _minutes > 0) {
              final totalSeconds = _hours * 3600 + _minutes * 60;
              final newActivity = Activity(
                name: _nameController.text.trim(),
                dailyLimit: totalSeconds,
                remainingTime: totalSeconds,
              );
              Navigator.of(context).pop(newActivity);
            }
          },
          style: ElevatedButton.styleFrom(
            padding: EdgeInsets.symmetric(
              horizontal: 16, // Reduced from 16
              vertical: 8, // Reduced from 8
            ),
            minimumSize: Size(
              80, // Reduced from 80
              36, // Reduced from 36
            ),
          ),
          child: Text(
            'Add',
            style: TextStyle(
              fontSize: 14, // Reduced from 14
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

///
/// Activity: Model class for an activity and its timer state
///
class Activity {
  final String name;
  final int dailyLimit; // in seconds
  int remainingTime; // in seconds
  bool isRunning;
  bool isPaused;

  Activity({
    required this.name,
    required this.dailyLimit,
    required this.remainingTime,
    this.isRunning = false,
    this.isPaused = false,
  });

  // --- Convert Activity to JSON for storage ---
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'dailyLimit': dailyLimit,
      'remainingTime': remainingTime,
      'isRunning': isRunning,
      'isPaused': isPaused,
    };
  }

  // --- Create Activity from JSON ---
  factory Activity.fromJson(Map<String, dynamic> json) {
    return Activity(
      name: json['name'],
      dailyLimit: json['dailyLimit'],
      remainingTime: json['remainingTime'],
      isRunning: json['isRunning'] ?? false,
      isPaused: json['isPaused'] ?? false,
    );
  }
}
