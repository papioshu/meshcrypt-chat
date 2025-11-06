import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/contact_model.dart';
import '../services/database_service.dart';

class ContactListWidget extends StatefulWidget {
  const ContactListWidget({super.key});

  @override
  State<ContactListWidget> createState() => _ContactListWidgetState();
}

class _ContactListWidgetState extends State<ContactListWidget> {
  List<Contact> _contacts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    try {
      final dbService = context.read<DatabaseService>();
      if (dbService.isInitialized) {
        // This would be implemented with proper database calls
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_contacts.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 64,
              color: Colors.grey,
            ),
            SizedBox(height: 16),
            Text(
              'No contacts yet',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Scan a QR code to add contacts',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _contacts.length,
      itemBuilder: (context, index) {
        final contact = _contacts[index];
        return ContactTile(contact: contact);
      },
    );
  }
}

class ContactTile extends StatelessWidget {
  final Contact contact;

  const ContactTile({super.key, required this.contact});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: contact.status.color,
          child: Text(
            contact.displayName.substring(0, 1).toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(contact.displayName),
        subtitle: Text(
          '${contact.status.description} • ${contact.messageCount} messages',
        ),
        trailing: contact.isOnline 
          ? const Icon(Icons.circle, color: Colors.green, size: 12)
          : const Icon(Icons.circle, color: Colors.grey, size: 12),
        onTap: () {
          // Navigate to chat screen
          _showContactOptions(context);
        },
      ),
    );
  }

  void _showContactOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => ContactOptionsBottomSheet(contact: contact),
    );
  }
}

class ContactOptionsBottomSheet extends StatelessWidget {
  final Contact contact;

  const ContactOptionsBottomSheet({super.key, required this.contact});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            contact.displayName,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.message),
            title: const Text('Send Message'),
            onTap: () {
              Navigator.pop(context);
              // Navigate to chat
            },
          ),
          ListTile(
            leading: const Icon(Icons.info),
            title: const Text('Contact Info'),
            onTap: () {
              Navigator.pop(context);
              // Show contact details
            },
          ),
          ListTile(
            leading: const Icon(Icons.block),
            title: Text(contact.isBlocked ? 'Unblock' : 'Block'),
            onTap: () {
              Navigator.pop(context);
              // Toggle block status
            },
          ),
        ],
      ),
    );
  }
}