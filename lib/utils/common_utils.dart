import 'package:flutter/material.dart';
import '../widgets/custom_dropdown.dart';

Future<void> showTicketModal({
  required BuildContext context,
  required String title,
  required String? initialTitle,
  required String? initialDescription,
  required String? initialFacility,
  required String? initialCategory,
  required List<String> facilityList,
  required List<String> categoryList,
  required Function(String title, String description, String facility, String category) onSave,
}) async {
  final TextEditingController titleController = TextEditingController(text: initialTitle);
  final TextEditingController descriptionController = TextEditingController(text: initialDescription);
  String? selectedFacility = initialFacility;
  String? selectedCategory = initialCategory;

  await showDialog(
    context: context,
    builder: (BuildContext context) {
      final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
      final dialogWidth = isLandscape ? MediaQuery.of(context).size.width * 0.6 : MediaQuery.of(context).size.width * 0.9;

      return AlertDialog(
        backgroundColor: const Color(0xFF1B2A49),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Center(
          child: Text(
            title,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
        content: SizedBox(
          width: dialogWidth,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Title',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: titleController,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Description',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: descriptionController,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    maxLines: isLandscape ? 2 : 4,
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Facility',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  CustomDropdown(
                    value: selectedFacility,
                    hint: 'Select Facility',
                    items: facilityList,
                    onChanged: (value) {
                      selectedFacility = value;
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Category',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  CustomDropdown(
                    value: selectedCategory,
                    hint: 'Select Category',
                    items: categoryList,
                    onChanged: (value) {
                      selectedCategory = value;
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.redAccent,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Cancel',
              style: TextStyle(fontSize: 18),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              if (titleController.text.isNotEmpty &&
                  descriptionController.text.isNotEmpty &&
                  selectedFacility != null &&
                  selectedCategory != null) {
                Navigator.of(context).pop();
                onSave(
                  titleController.text,
                  descriptionController.text,
                  selectedFacility!,
                  selectedCategory!,
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please fill all fields')),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.tealAccent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Save',
              style: TextStyle(fontSize: 18),
            ),
          ),
        ],
      );
    },
  );
}
