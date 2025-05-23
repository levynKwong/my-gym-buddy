import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:gym_buddy_app/models/exercise.dart';
import 'package:gym_buddy_app/models/rep_set.dart';
import 'package:gym_buddy_app/models/workout.dart';
import 'package:gym_buddy_app/sql_queries.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  static DatabaseHelper get instance => _instance;

  static Database? database;

  static Future<String> getDatabasePath() async {
    var databasesPath = await getDatabasesPath();
    if (kDebugMode) print(databasesPath);
    return '$databasesPath/gym_buddy.db';
  }

  static Future<String?> importDatabase(File newDatabase) async {
    if (newDatabase.path.split('.').last != 'db') {
      return "Invalid file type";
    }

    await deleteDatabase(await getDatabasePath());
    File newFile = await newDatabase.copy(await getDatabasePath());
    await newFile.rename(await getDatabasePath());
    await openLocalDatabase(reopen: true);

    return null;
  }

  static Future<void> exportDatabase() async {
    Share.shareXFiles([XFile(await getDatabasePath())],
        subject: 'Gym Buddy Database');
  }

  static Future<List<Workout>> getTodayRecommendedWorkouts() async {
    if (database == null) {
      await openLocalDatabase();
    }

    // workout_day is in format 1234567 where 1 is monday and 7 is sunday
    int day = DateTime.now().weekday;

    final rawWorkout = await database!
        .query('workout_templates', where: "workout_day like '%$day%'");

    List<Workout> workouts = [];
    for (final record in rawWorkout) {
      Workout workout = Workout.fromJson(
        record,
      );
      workouts.add(workout);
    }

    return workouts;
  }

  static Future<bool> saveExercise(Exercise exercise) async {
    if (database == null) {
      await openLocalDatabase();
    }

    var data = exercise.toJson();
    var safeData = {
      'exercise_name': data['exercise_name'],
      'exercise_video': data['exercise_video'],
      'exercise_description': data['exercise_description'],
      'exercise_category': data['exercise_category'],
      'exercise_difficulty': data['exercise_difficulty'],
      'images': json.encode(data['images']),
    };

    database!.insert(
      'exercises',
      safeData,
    );

    return true;
  }

  static Future<bool> saveWorkoutSession(Workout workout, int duration) async {
    var rawWorkoutID = await database!.insert('workout_session', {
      'workout_template_id': workout.id,
      'duration': duration,
      'workout_session_name': workout.name,
      'start_time': workout.startTime != null
          ? workout.startTime!.toIso8601String()
          : DateTime.now()
              .subtract(Duration(seconds: duration))
              .toIso8601String(),
    });

    int index = 0;
    for (final exercise in workout.exercises!) {
      var repSet = {'sets': []};

      for (final set in exercise.sets) {
        repSet['sets']!
            .add({'reps': set.reps, 'weight': set.weight, 'note': set.note});
      }

      final workoutSessionExercise = <String, dynamic>{
        "exercise_id": int.parse(exercise.id!),
        "workout_session_id": rawWorkoutID,
        "rep_set": json.encode(repSet),
        "exercise_index": index,
      };

      await database!
          .insert('workout_session_exercises', workoutSessionExercise);
      index++;
    }

    return true;
  }
  static Future<Map<String, dynamic>> deleteExercise(Exercise exercise) async {
    final rawWorkout = await database!.query('workout_template_exercises',
        where: 'exercise_id = ?', whereArgs: [exercise.id]);

    

    int workoutCount = rawWorkout.length;

    if (workoutCount > 0) {
      return {
        'success': false, 
        'workoutCount': workoutCount
      };
    }

    await database!
        .delete('exercises', where: 'id = ?', whereArgs: [exercise.id]);

    return {'success': true, 'workoutCount': 0};
  }

  static Future<bool> updateExercise(Exercise exercise) async {
    var data = exercise.toJson();
    var safeData = {
      'exercise_name': data['exercise_name'],
      'exercise_video': data['exercise_video'],
      'exercise_description': data['exercise_description'],
      'exercise_category': data['exercise_category'],
      'exercise_difficulty': data['exercise_difficulty'],
      'images': json.encode(data['images']),
    };

    database!.update('exercises', safeData,
        where: 'id = ?', whereArgs: [exercise.id]);

    return true;
  }

  static Future<bool> deleteWorkoutSession(Workout workout) async {
    print('deleting workout ${workout.id}');

    await database!
        .delete('workout_session', where: 'id = ?', whereArgs: [workout.id]);
    await database!.delete('workout_session_exercises',
        where: 'workout_session_id = ?', whereArgs: [workout.id]);

    return true;
  }

  static Future<bool> updateWorkoutSession(Workout workout) async {
    //todo: improve that :D
    await deleteWorkoutSession(workout);
    await saveWorkoutSession(workout, workout.duration!);

    return true;
  }

  static Future<bool> updateWorkout(Workout workout) async {
    //todo: improve that :D
    await deleteWorkout(workout);
    await saveWorkout(workout);

    return true;
  }

  static Future<bool> deleteWorkout(Workout workout) async {
    await database!
        .delete('workout_templates', where: 'id = ?', whereArgs: [workout.id]);

    await database!.delete('workout_template_exercises',
        where: 'workout_template_id = ?', whereArgs: [workout.id]);

    return true;
  }

  static Future<bool> saveWorkout(Workout workout) async {
    print(workout.getWorkoutDaysAsInt());
    var rawWorkoutID = await database!.insert('workout_templates', {
      'workout_name': workout.name,
      'workout_description':
          workout.description == '' ? null : workout.description,
      "workout_day": workout.getWorkoutDaysAsInt() == 0
          ? null
          : workout.getWorkoutDaysAsInt(),
    });

    int index = 0;
    for (final exercise in workout.exercises!) {
      var repSet = {'sets': []};

      for (final set in exercise.sets) {
        repSet['sets']!
            .add({'reps': set.reps, 'weight': set.weight, 'note': set.note});
      }

      final workoutTemplateExercise = <String, dynamic>{
        "exercise_id": int.parse(exercise.id!),
        "workout_template_id": rawWorkoutID,
        "rep_set": json.encode(repSet),
        "exercise_index": index,
      };

      await database!
          .insert('workout_template_exercises', workoutTemplateExercise);
      index++;
    }

    return true;
  }

  static Future<List<Exercise>> getExercises() async {
    if (database == null) {
      await openLocalDatabase();
    }

    final List<Map<String, dynamic>> maps = await database!.query('exercises');
    return List.generate(maps.length, (i) {
      var map = Map<String, dynamic>.from(maps[i]); // Make a mutable copy
      if (map['images'] != null) {
        if (map['images'] is String) {
          try {
            map['images'] = json.decode(map['images']);
            print('images: ${map['images']}');
          } catch (e) {
            print('Error parsing images JSON: $e');
            map['images'] = [];
          }
        }
      }
      return Exercise.fromJson(map);
    });
  }

  static Future<dynamic> getWeeklyStatistics() async {
    if (database == null) {
      await openLocalDatabase();
    }

    final rawWorkout =
        await database!.query('workout_session', orderBy: 'start_time DESC');

    int totalDuration = 0;
    double totalWeightLifted = 0;
    int totalWorkouts = 0;

    Map<DateTime, double> dailyTotalDuration = {};
    Map<DateTime, double> dailyTotalWeightLifted = {};

    for (final record in rawWorkout) {
      totalDuration += record['duration'] as int;

      // only date without time
      var date =
          DateTime.parse(record['start_time'].toString().substring(0, 10));

      dailyTotalDuration[date] = (dailyTotalDuration[date] ?? 0) +
          ((record['duration'] as int) / 3600);

      totalWorkouts++;

      final rawExercises = await database!.query('workout_session_exercises',
          where: 'workout_session_id = ?', whereArgs: [record['id']]);
      for (final exercise in rawExercises) {
        final repSet = exercise['rep_set'];
        final repSetMap = json.decode(repSet.toString());

        for (final set in repSetMap['sets']) {
          totalWeightLifted += (set['weight'] * set['reps']);

          dailyTotalWeightLifted[date] = (dailyTotalWeightLifted[date] ?? 0) +
              ((set['weight'] * set['reps']));
        }
      }
    }

    print({
      'totalDuration': totalDuration,
      'totalWeightLifted': totalWeightLifted,
      'totalWorkouts': totalWorkouts,
      'dailyTotalDuration': dailyTotalDuration,
      'dailyTotalWeightLifted': dailyTotalWeightLifted
    });

    return {
      'totalDuration': totalDuration,
      'totalWeightLifted': totalWeightLifted,
      'totalWorkouts': totalWorkouts,
      'dailyTotalDuration': dailyTotalDuration,
      'dailyTotalWeightLifted': dailyTotalWeightLifted
    };
  }

  static Future<List<Workout>> getAllWorkoutSessions() async {
    if (database == null) {
      await openLocalDatabase();
    }

    final rawWorkout =
        await database!.query('workout_session', orderBy: 'start_time DESC');

    List<Workout> workouts = [];
    for (final record in rawWorkout) {
      Workout workout = Workout(
          id: record['id'].toString(),
          name: record['workout_session_name'] != null
              ? record['workout_session_name'].toString()
              : 'unnamed workout',
          exercises: []);

      workout.startTime = DateTime.parse(record['start_time'].toString());
      workout.duration = record['duration'] as int;
      workout.totalWeightLifted = 0;

      workouts.add(workout);

      final rawExercises = await database!.query('workout_session_exercises',
          where: 'workout_session_id = ?', whereArgs: [record['id']]);

      for (final exercise in rawExercises) {
        final exerciseID = exercise['exercise_id'].toString();
        final exerciseRecord = await getExerciseGivenID(exerciseID);
        final exerciseObject = Exercise.fromJson(exerciseRecord.toJson());

        // convert rep_set to list of rep_set
        final repSet = exercise['rep_set'];
        final repSetMap = json.decode(repSet.toString());

        for (final set in repSetMap['sets']) {
          exerciseObject.sets.add(RepSet.fromJson(set));
          workout.totalWeightLifted =
              workout.totalWeightLifted! + (set['weight'] * set['reps']);
        }

        workout.exercises!.add(exerciseObject);
      }
    }

    return workouts;
  }

  static Future<Exercise> getExerciseGivenID(String id) async {
    final record =
        await database!.query('exercises', where: 'id = ?', whereArgs: [id]);

    // get the last record from session exercises
    final previousRecord = await database!.query('workout_session_exercises',
        where: 'exercise_id = ?',
        whereArgs: [id],
        orderBy: 'id DESC',
        limit: 1);

    Exercise exercise = Exercise.fromJson(record.first);
    if (previousRecord.isNotEmpty) {
      var decodedJson = json.decode(previousRecord.first['rep_set'].toString());
      List<dynamic> setsJson = decodedJson['sets'];
      exercise.previousSets =
          setsJson.map((set) => RepSet.fromJson(set)).toList();
    }

    return exercise;
  }

  static Future<List<Workout>> getWorkoutList() async {
    if (database == null) {
      await openLocalDatabase();
    }

    final rawWorkout = await database!.query('workout_templates');

    if (kDebugMode) print(rawWorkout);

    List<Workout> workouts = [];
    for (final record in rawWorkout) {
      Workout workout = Workout.fromJson(
        record,
      );
      workouts.add(workout);
    }

    return workouts;
  }

  static Future<Workout> getWorkoutGivenID(String id) async {
    final record = await database!
        .query('workout_templates', where: 'id = ?', whereArgs: [id]);

    if (record.isEmpty) {
      return Workout(name: 'no name', id: '-1');
    }

    final rawExercises = await database!.query('workout_template_exercises',
        where: 'workout_template_id = ?', whereArgs: [id]);

    List<Exercise> exercises = [];

    for (final exercise in rawExercises) {
      final exerciseID = exercise['exercise_id'].toString();
      final exerciseRecord = await getExerciseGivenID(exerciseID);
      final exerciseObject = Exercise.fromJson(exerciseRecord.toJson());

      // convert rep_set to list of rep_set
      final repSet = exercise['rep_set'];
      final repSetMap = json.decode(repSet.toString());

      for (final set in repSetMap['sets']) {
        exerciseObject.sets.add(RepSet.fromJson(set));
      }

      exercises.add(exerciseObject);
    }

    Workout workout = Workout.fromJson(record.first);

    workout.exercises = exercises;

    return workout;
  }

  static Future<Database> openLocalDatabase(
      {bool newDatabase = false, bool reopen = false}) async {
    if (Platform.isWindows) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    if (newDatabase) {
      await deleteDatabase(await getDatabasePath());
      database = null;
    }

    if (database == null || reopen) {
      database = await openDatabase(
        await getDatabasePath(),
        version: 3, // Current version
        onCreate: (db, version) async {
          // For new database, create with latest version
          for (final query in SqlQueries.databaseCreationV3) {
            await db.execute(query);
          }
        },
        onOpen: (db) async {
          // Check current database version
          var version = await db.getVersion();
          if (version < 3) {
            // Force upgrade if not at latest version
            for (final query in SqlQueries.databaseUpgradeV2toV3) {
              try {
                await db.execute(query);
              } catch (e) {
                print(
                    'Migration error (can be ignored if column already exists): $e');
              }
            }
            await db.setVersion(3);
          }
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          print('Upgrading database from version $oldVersion to $newVersion');
          if (oldVersion < 2) {
            for (final query in SqlQueries.databaseUpgradeV1toV2) {
              await db.execute(query);
            }
          }
          if (oldVersion < 3) {
            for (final query in SqlQueries.databaseUpgradeV2toV3) {
              try {
                await db.execute(query);
              } catch (e) {
                print(
                    'Migration error (can be ignored if column already exists): $e');
              }
            }
          }
        },
      );
      return database!;
    }

    return database!;
  }

  static void resetDatabase() async {
    await openLocalDatabase(newDatabase: true);
  }

  static Future<List<String>> getCategories() async {
    if (database == null) {
      await openLocalDatabase();
    }

    final result = await database!.query(
      'categories',
      columns: ['name'],
      orderBy: 'name ASC',
    );

    return result.map((row) => row['name'] as String).toList();
  }

  static Future<List<String>> getDifficulties() async {
    if (database == null) {
      await openLocalDatabase();
    }

    final result = await database!.query(
      'difficulties',
      columns: ['name'],
      orderBy: 'name ASC',
    );

    return result.map((row) => row['name'] as String).toList();
  }

  static Future<bool> addCategory(String category) async {
    if (database == null) {
      await openLocalDatabase();
    }

    try {
      await database!.insert(
        'categories',
        {'name': category},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      return true;
    } catch (e) {
      if (kDebugMode) print('Error adding category: $e');
      return false;
    }
  }

  static Future<bool> addDifficulty(String difficulty) async {
    if (database == null) {
      await openLocalDatabase();
    }

    try {
      await database!.insert(
        'difficulties',
        {'name': difficulty},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      return true;
    } catch (e) {
      if (kDebugMode) print('Error adding difficulty: $e');
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> getExerciseHistory(String exerciseId) async {
    if (database == null) {
      await openLocalDatabase();
    }

    // Get all workout sessions containing this exercise
    final List<Map<String, dynamic>> sessionExercises = await database!.rawQuery('''
      SELECT 
        ws.id as session_id, 
        ws.start_time, 
        ws.workout_session_name, 
        wse.rep_set
      FROM workout_session ws
      JOIN workout_session_exercises wse ON ws.id = wse.workout_session_id
      WHERE wse.exercise_id = ?
      ORDER BY ws.start_time DESC
    ''', [exerciseId]);

    // Format the data for display
    List<Map<String, dynamic>> history = [];
    
    for (var item in sessionExercises) {
      final repSetMap = json.decode(item['rep_set']);
      final sets = repSetMap['sets'] as List;
      
      history.add({
        'sessionId': item['session_id'],
        'date': DateTime.parse(item['start_time']),
        'workoutName': item['workout_session_name'] ?? 'Unnamed Workout',
        'sets': sets.map((set) => RepSet.fromJson(set)).toList(),
      });
    }
    
    return history;
  }
  static Future<bool> saveTemporaryWorkout(Workout workout, int duration) async {
    if (database == null) {
      await openLocalDatabase();
    }
    
    try {
      // Use a transaction to avoid database locking issues
      return await database!.transaction((txn) async {
        // First, clear any existing temporary workout
        await txn.delete('temporary_workout');
        
        // Convert the workout to JSON format
        var workoutJson = workout.toJson();
        
        if (kDebugMode) {
          print('Saving temporary workout: ${json.encode(workoutJson)}');
          print('Duration: $duration');
        }
        
        // Insert the new temporary workout
        await txn.insert('temporary_workout', {
          'workout_template_id': workout.id,
          'workout_data': json.encode(workoutJson),
          'start_time': workout.startTime != null 
              ? workout.startTime!.toIso8601String() 
              : DateTime.now().toIso8601String(),
          'duration': duration,
        });
        
        if (kDebugMode) {
          print('Temporary workout saved with duration: $duration');
        }
        
        return true;
      });
    } catch (e) {
      if (kDebugMode) {
        print('Error saving temporary workout: $e');
      }
      return false;
    }
  }
    static Future<bool> clearTemporaryWorkout() async {
    if (database == null) {
      await openLocalDatabase();
    }
    
    try {
      // Use a transaction for database operations
      return await database!.transaction((txn) async {
        await txn.delete('temporary_workout');
        return true;
      });
    } catch (e) {
      if (kDebugMode) {
        print('Error clearing temporary workout: $e');
      }
      return false;
    }
  }
    static Future<bool> hasTemporaryWorkout() async {
    if (database == null) {
      await openLocalDatabase();
    }
    
    try {
      // Use a transaction for database operations
      return await database!.transaction((txn) async {
        final result = await txn.query('temporary_workout');
        return result.isNotEmpty;
      });
    } catch (e) {
      if (kDebugMode) {
        print('Error checking for temporary workout: $e');
      }
      return false;
    }
  }
    // Helper method to parse basic workout data
  static Workout _parseBasicWorkoutData(Map<String, dynamic> workoutData) {
    final workoutJson = json.decode(workoutData['workout_data'] as String);
    final workout = Workout.fromJson(workoutJson);
    workout.startTime = DateTime.parse(workoutData['start_time'] as String);
    workout.duration = workoutData['duration'] as int;
    return workout;
  }
  
  // Helper method to load exercise sets
  static List<RepSet> _loadSets(List<dynamic>? setsData) {
    if (setsData == null) return [];
    return setsData.map((setData) => RepSet.fromJson(setData)).toList();
  }
  
  // Helper method to load exercises
  static List<Exercise> _loadExercises(List<dynamic>? exercisesData) {
    if (exercisesData == null) return [];
    
    return exercisesData.map((exercise) {
      final loadedExercise = Exercise.fromJson(exercise);
      
      // Explicitly load sets with their completed state
      if (exercise['sets'] != null) {
        loadedExercise.sets = _loadSets(exercise['sets']);
      }
      
      return loadedExercise;
    }).toList();
  }
  
  // Helper method to log workout details in debug mode
  static void _logWorkoutDebugInfo(Workout workout) {
    if (!kDebugMode) return;
    
    print('Recovered workout: ${workout.name} with ${workout.exercises?.length ?? 0} exercises');
    
    final exercises = workout.exercises;
    if (exercises == null) return;
    
    for (var ex in exercises) {
      print('  Exercise: ${ex.name} with ${ex.sets.length} sets');
      for (var set in ex.sets) {
        print('    Set: ${set.reps} reps, ${set.weight} kg, completed: ${set.completed}');
      }
    }
  }
  
  static Future<Workout?> getTemporaryWorkout() async {
    if (database == null) {
      await openLocalDatabase();
    }
    
    try {
      return await database!.transaction((txn) async {
        final result = await txn.query('temporary_workout');
        if (result.isEmpty) return null;
        
        final workoutData = result.first;
        final workoutJson = json.decode(workoutData['workout_data'] as String);
        
        // Parse basic workout data
        final workout = _parseBasicWorkoutData(workoutData);
        
        // Load exercises if available
        if (workoutJson['exercises'] != null) {
          workout.exercises = _loadExercises(workoutJson['exercises']);
        }
        
        // Log debug info
        _logWorkoutDebugInfo(workout);
        
        return workout;
      });
    } catch (e) {
      if (kDebugMode) print('Error retrieving temporary workout: $e');
      return null;
    }
  }
}
