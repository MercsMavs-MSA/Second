import 'package:flutter/material.dart';
import 'package:transparent_image/transparent_image.dart';

import 'backend.dart';

class ManagementPage extends StatefulWidget {
  final AttendanceTrackerBackend backend;
  final List<Member> members;
  final List<String> allowedLocations;

  const ManagementPage(
    this.backend,
    this.members, {
    super.key,
    this.allowedLocations = const ["Shop"],
  });

  @override
  State<ManagementPage> createState() => _ManagementPageState();
}

class _ManagementPageState extends State<ManagementPage> {
  final TextEditingController _searchQuery = TextEditingController();

  bool _sortAscending = true;
  String _sortCriteria = 'name'; // 'name' or 'status'

  List<Member> _getFilteredMembers(List<Member> members) {
    final List<Member> filtered = members
        .where(
          (member) => member
              .getVisualName()
              .toLowerCase()
              .contains(_searchQuery.text.toLowerCase()),
        )
        .toList();

    if (_sortCriteria != 'none') {
      filtered.sort((a, b) {
        int result;
        if (_sortCriteria == 'name') {
          result = a.getVisualName().toLowerCase().compareTo(
            b.getVisualName().toLowerCase(),
          );
        } else {
          result = a.status.index.compareTo(b.status.index);
        }
        return _sortAscending ? result : -result;
      });
    }

    return filtered;
  }

  void _openMemberDetails(Member member) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MemberDetailPage(
          widget.backend,
          member,
          allowedLocations: widget.allowedLocations,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchQuery.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Member Management")),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchQuery,
                    decoration: InputDecoration(
                      hintText: 'Search name...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onChanged: (value) {
                      setState(() {});
                    },
                  ),
                ),
                SizedBox(width: 8.0),
                PopupMenuButton<String>(
                  icon: Icon(Icons.filter_list),
                  tooltip: "Sort",
                  onSelected: (value) {
                    setState(() {
                      if (value == 'name_asc') {
                        _sortCriteria = 'name';
                        _sortAscending = true;
                      } else if (value == 'name_desc') {
                        _sortCriteria = 'name';
                        _sortAscending = false;
                      } else if (value == 'status_asc') {
                        _sortCriteria = 'status';
                        _sortAscending = true;
                      } else if (value == 'status_desc') {
                        _sortCriteria = 'status';
                        _sortAscending = false;
                      } else if (value == 'none') {
                        _sortCriteria = 'none';
                        _sortAscending = false;
                      }
                    });
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'name_asc',
                      child: Row(
                        children: [
                          Icon(Icons.sort_by_alpha),
                          SizedBox(width: 8),
                          Text('Name (A-Z)'),
                          Spacer(),
                          if (_sortCriteria == "name" && _sortAscending)
                            Icon(Icons.check),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'name_desc',
                      child: Row(
                        children: [
                          Icon(Icons.sort_by_alpha),
                          SizedBox(width: 8),
                          Text('Name (Z-A)'),
                          Spacer(),
                          if (_sortCriteria == "name" && !_sortAscending)
                            Icon(Icons.check),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'status_asc',
                      child: Row(
                        children: [
                          Icon(Icons.query_stats),
                          SizedBox(width: 8),
                          Text('Status (Present First)'),
                          Spacer(),
                          if (_sortCriteria == "status" && _sortAscending)
                            Icon(Icons.check),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'status_desc',
                      child: Row(
                        children: [
                          Icon(Icons.query_stats),
                          SizedBox(width: 8),
                          Text('Status (Out First)'),
                          Spacer(),
                          if (_sortCriteria == "status" && !_sortAscending)
                            Icon(Icons.check),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'none',
                      child: Row(
                        children: [
                          Icon(Icons.filter_alt_off),
                          SizedBox(width: 8),
                          Text('Do Not Sort'),
                          Spacer(),
                          if (_sortCriteria == "none") Icon(Icons.check),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(width: 8.0),
              ],
            ),
            SizedBox(height: 8.0),
            Expanded(
              child: ValueListenableBuilder<List<Member>>(
                valueListenable: widget.backend.attendance,
                builder: (context, attendanceValue, child) {
                  final filtered = _getFilteredMembers(attendanceValue);
                  if (filtered.isEmpty) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.no_accounts,
                          size: 128,
                          color: Theme.of(context).colorScheme.primaryFixedDim,
                        ),
                        Text("No members found matching the search criteria"),
                      ],
                    );
                  }
                  return ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final member = filtered[index];
                      return ListTile(
                        leading: Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            CircleAvatar(
                              child: member.pfpUrl != null
                                  ? ClipOval(
                                      child: FadeInImage.memoryNetwork(
                                        placeholder: kTransparentImage,
                                        image: member.pfpUrl!,
                                      ),
                                    )
                                  : Builder(
                                      builder: (context) {
                                        List<String> nameParts = member
                                            .getVisualName()
                                            .split(' ');
                                        nameParts.removeWhere(
                                          (val) => val.isEmpty,
                                        );
                                        return Text(
                                          nameParts
                                              .map((part) => part[0])
                                              .take(2)
                                              .join(),
                                        );
                                      },
                                    ),
                            ),
                            Stack(
                              alignment: AlignmentGeometry.center,
                              children: [
                                Icon(
                                  Icons.circle,
                                  color:
                                      Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainer,
                                  size: 16,
                                ),
                                Icon(
                                  Icons.circle,
                                  color:
                                      member.status == AttendanceStatus.present
                                      ? Colors.green
                                      : Colors.red,
                                  size: 12,
                                ),
                              ],
                            ),
                          ],
                        ),
                        title: Text(member.getVisualName()),
                        subtitle: Text(
                          member.getTitles()?.join(" · ") ??
                              "Error loading title, please refresh members",
                        ),
                        onTap: () {
                          _openMemberDetails(member);
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MemberDetailPage extends StatefulWidget {
  final AttendanceTrackerBackend backend;
  final Member member;
  final List<String> allowedLocations;

  const MemberDetailPage(
    this.backend,
    this.member, {
    super.key,
    this.allowedLocations = const ["Shop"],
  });

  @override
  State<MemberDetailPage> createState() => _MemberDetailPageState();
}

class _MemberDetailPageState extends State<MemberDetailPage> {
  String? _selectedLocation;

  @override
  void initState() {
    super.initState();
    _selectedLocation = widget.allowedLocations.first;
  }

  Future<DateTime?> _pickCustomTime(BuildContext context) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
    );
    if (date == null) return null;
    if (!context.mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Widget _buildAvatar(Member member) {
    Widget avatarContent = member.pfpUrl != null
        ? ClipOval(
            child: FadeInImage.memoryNetwork(
              placeholder: kTransparentImage,
              image: member.pfpUrl!,
            ),
          )
        : Builder(
            builder: (context) {
              List<String> nameParts = member.getVisualName().split(' ');
              nameParts.removeWhere((val) => val.isEmpty);
              return Text(
                nameParts.map((part) => part[0]).take(2).join(),
                style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
              );
            },
          );

    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        CircleAvatar(radius: 64, child: avatarContent),
        Stack(
          alignment: AlignmentGeometry.center,
          children: [
            Icon(
              Icons.circle,
              color: Theme.of(context).colorScheme.surfaceContainer,
              size: 36,
            ),
            Icon(
              Icons.circle,
              color: member.status == AttendanceStatus.present
                  ? Colors.green
                  : Colors.red,
              size: 28,
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Member Details")),
      body: ValueListenableBuilder<List<Member>>(
        valueListenable: widget.backend.attendance,
        builder: (context, attendanceValue, child) {
          final Member member = attendanceValue.firstWhere(
            (m) => m.id == widget.member.id,
            orElse: () => widget.member,
          );

          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(child: _buildAvatar(member)),
                  SizedBox(height: 16),
                  Text(
                    member.getVisualName(),
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    member.getTitles()?.join(" · ") ??
                        "Error loading title, please refresh members",
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("ID: ${member.id}"),
                          Text("Nickname: ${member.nickname ?? member.name}"),
                          Text(
                            "Status: ${member.status == AttendanceStatus.present ? "Present${member.location != null ? " (${member.location})" : ""}" : "Out"}",
                          ),
                          Text("Titles: ${member.titles}"),
                          Text("Groups: ${member.groups}"),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            "Time Clock",
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          SizedBox(height: 12),
                          if (member.status == AttendanceStatus.out) ...[
                            DropdownButtonFormField<String>(
                              initialValue: _selectedLocation,
                              onChanged: (value) {
                                setState(() {
                                  _selectedLocation = value!;
                                });
                              },
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                labelText: "Location",
                              ),
                              items: widget.allowedLocations.map((location) {
                                return DropdownMenuItem<String>(
                                  value: location,
                                  child: Text(location),
                                );
                              }).toList(),
                            ),
                            SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton(
                                    onPressed: () {
                                      widget.backend.clockIn(
                                        member.id,
                                        _selectedLocation!,
                                      );
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16.0,
                                      ),
                                      child: Text(
                                        "Clock In (Now)",
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () async {
                                      final customTime = await _pickCustomTime(
                                        context,
                                      );
                                      if (customTime != null) {
                                        widget.backend.clockIn(
                                          member.id,
                                          _selectedLocation!,
                                          time: customTime,
                                        );
                                      }
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16.0,
                                      ),
                                      child: Text(
                                        "Clock In (Custom Time)",
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ] else ...[
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton(
                                    onPressed: () {
                                      widget.backend.clockOut(member.id);
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16.0,
                                      ),
                                      child: Text(
                                        "Clock Out (Now)",
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () async {
                                      final customTime = await _pickCustomTime(
                                        context,
                                      );
                                      if (customTime != null) {
                                        widget.backend.clockOut(
                                          member.id,
                                          time: customTime,
                                        );
                                      }
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16.0,
                                      ),
                                      child: Text(
                                        "Clock Out (Custom Time)",
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
