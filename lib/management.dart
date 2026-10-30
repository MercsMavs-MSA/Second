import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:second/member_timeline.dart';
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
      appBar: AppBar(title: const Text("Member Management")),
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
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onChanged: (value) {
                      setState(() {});
                    },
                  ),
                ),
                const SizedBox(width: 8.0),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.filter_list),
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
                          const Icon(Icons.sort_by_alpha),
                          const SizedBox(width: 8),
                          const Text('Name (A-Z)'),
                          const Spacer(),
                          if (_sortCriteria == "name" && _sortAscending)
                            const Icon(Icons.check),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'name_desc',
                      child: Row(
                        children: [
                          const Icon(Icons.sort_by_alpha),
                          const SizedBox(width: 8),
                          const Text('Name (Z-A)'),
                          const Spacer(),
                          if (_sortCriteria == "name" && !_sortAscending)
                            const Icon(Icons.check),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'status_asc',
                      child: Row(
                        children: [
                          const Icon(Icons.query_stats),
                          const SizedBox(width: 8),
                          const Text('Status (Present First)'),
                          const Spacer(),
                          if (_sortCriteria == "status" && _sortAscending)
                            const Icon(Icons.check),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'status_desc',
                      child: Row(
                        children: [
                          const Icon(Icons.query_stats),
                          const SizedBox(width: 8),
                          const Text('Status (Out First)'),
                          const Spacer(),
                          if (_sortCriteria == "status" && !_sortAscending)
                            const Icon(Icons.check),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'none',
                      child: Row(
                        children: [
                          const Icon(Icons.filter_alt_off),
                          const SizedBox(width: 8),
                          const Text('Do Not Sort'),
                          const Spacer(),
                          if (_sortCriteria == "none") const Icon(Icons.check),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 8.0),
              ],
            ),
            const SizedBox(height: 8.0),
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
                        const Text("No members found matching the search criteria"),
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
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainer,
                                  size: 16,
                                ),
                                Icon(
                                  Icons.circle,
                                  color: member.status == AttendanceStatus.present
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
  late final MemberTimelineManager _timelineManager;
  bool _isLoading = false;
  List<MemberShift>? _shifts;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _timelineManager = MemberTimelineManager(widget.backend);
    _loadTimeline();
  }

  Future<void> _loadTimeline() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await _timelineManager.getMemberTimeline(
        widget.member.id,
      );
      if (mounted) {
        setState(() {
          _shifts = result;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<DateTime?> _pickDateTime(
    BuildContext context, {
    DateTime? initialDateTime,
  }) async {
    final now = DateTime.now();
    final initial = initialDateTime ?? now;

    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now.subtract(const Duration(days: 365 * 2)),
      lastDate: now.add(const Duration(days: 1)),
    );
    if (date == null || !context.mounted) return null;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return null;

    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _showAddShiftDialog() async {
    DateTime clockInTime = DateTime.now();
    String clockInLocation = widget.allowedLocations.first;
    bool includeClockOut = false;
    DateTime clockOutTime = DateTime.now().add(const Duration(hours: 1));

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final dateFormat = DateFormat.yMMMd().add_jm();
            return AlertDialog(
              title: const Text('Add Shift'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Clock-In Time:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await _pickDateTime(context, initialDateTime: clockInTime);
                        if (picked != null) {
                          setDialogState(() {
                            clockInTime = picked;
                          });
                        }
                      },
                      icon: const Icon(Icons.calendar_today, size: 18),
                      label: Text(dateFormat.format(clockInTime)),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: clockInLocation,
                      decoration: const InputDecoration(
                        labelText: 'Clock-In Location',
                        border: OutlineInputBorder(),
                      ),
                      items: widget.allowedLocations.map((loc) {
                        return DropdownMenuItem(value: loc, child: Text(loc));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() {
                            clockInLocation = val;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Include Clock-Out'),
                      value: includeClockOut,
                      onChanged: (val) {
                        setDialogState(() {
                          includeClockOut = val ?? false;
                        });
                      },
                    ),
                    if (includeClockOut) ...[
                      const SizedBox(height: 8),
                      const Text('Clock-Out Time:', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await _pickDateTime(context, initialDateTime: clockOutTime);
                          if (picked != null) {
                            setDialogState(() {
                              clockOutTime = picked;
                            });
                          }
                        },
                        icon: const Icon(Icons.calendar_today, size: 18),
                        label: Text(dateFormat.format(clockOutTime)),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final errorColor = Theme.of(context).colorScheme.error;
                    Navigator.pop(dialogContext);
                    try {
                      await _timelineManager.createShift(
                        widget.member.id,
                        clockInTime: clockInTime,
                        clockInLocation: clockInLocation,
                        clockOutTime: includeClockOut ? clockOutTime : null,
                      );
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Shift added successfully')),
                      );
                      _loadTimeline();
                    } catch (e) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text('Failed to add shift: $e'),
                          backgroundColor: errorColor,
                        ),
                      );
                    }
                  },
                  child: const Text('Save Shift'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showEditShiftDialog(MemberShift shift) async {
    DateTime clockInTime = shift.clockInTime;
    String clockInLocation = shift.clockInLocation;
    bool hasClockOut = shift.clockOutTime != null;
    DateTime clockOutTime = shift.clockOutTime ?? DateTime.now();

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final dateFormat = DateFormat.yMMMd().add_jm();
            return AlertDialog(
              title: const Text('Edit Shift'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Clock-In Time:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await _pickDateTime(context, initialDateTime: clockInTime);
                        if (picked != null) {
                          setDialogState(() {
                            clockInTime = picked;
                          });
                        }
                      },
                      icon: const Icon(Icons.calendar_today, size: 18),
                      label: Text(dateFormat.format(clockInTime)),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: widget.allowedLocations.contains(clockInLocation)
                          ? clockInLocation
                          : widget.allowedLocations.first,
                      decoration: const InputDecoration(
                        labelText: 'Clock-In Location',
                        border: OutlineInputBorder(),
                      ),
                      items: widget.allowedLocations.map((loc) {
                        return DropdownMenuItem(value: loc, child: Text(loc));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() {
                            clockInLocation = val;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Clocked Out'),
                      value: hasClockOut,
                      onChanged: (val) {
                        setDialogState(() {
                          hasClockOut = val ?? false;
                        });
                      },
                    ),
                    if (hasClockOut) ...[
                      const SizedBox(height: 8),
                      const Text('Clock-Out Time:', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await _pickDateTime(context, initialDateTime: clockOutTime);
                          if (picked != null) {
                            setDialogState(() {
                              clockOutTime = picked;
                            });
                          }
                        },
                        icon: const Icon(Icons.calendar_today, size: 18),
                        label: Text(dateFormat.format(clockOutTime)),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final errorColor = Theme.of(context).colorScheme.error;
                    Navigator.pop(dialogContext);
                    try {
                      await _timelineManager.editShift(
                        shift,
                        newClockInTime: clockInTime,
                        newClockInLocation: clockInLocation,
                        newClockOutTime: hasClockOut ? clockOutTime : null,
                      );
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Shift updated successfully')),
                      );
                      _loadTimeline();
                    } catch (e) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text('Failed to update shift: $e'),
                          backgroundColor: errorColor,
                        ),
                      );
                    }
                  },
                  child: const Text('Save Changes'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showDeleteShiftDialog(MemberShift shift) async {
    await showDialog(
      context: context,
      builder: (dialogContext) {
        final dateFormat = DateFormat.yMMMd().add_jm();
        final inStr = dateFormat.format(shift.clockInTime);
        final outStr = shift.clockOutTime != null
            ? dateFormat.format(shift.clockOutTime!)
            : 'Active';

        return AlertDialog(
          title: const Text('Delete Shift'),
          content: Text(
            'Are you sure you want to delete this shift?\n\n'
            'Clock-In: $inStr\n'
            'Clock-Out: $outStr\n\n'
            'Per shift coupling rules, deleting this shift will remove both the Clock-In and Clock-Out records.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final errorColor = Theme.of(context).colorScheme.error;
                Navigator.pop(dialogContext);
                try {
                  await _timelineManager.deleteShift(shift);
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Shift deleted successfully')),
                  );
                  _loadTimeline();
                } catch (e) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Failed to delete shift: $e'),
                      backgroundColor: errorColor,
                    ),
                  );
                }
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else {
      return '${minutes}m';
    }
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
                style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
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

  Widget _buildShiftCard(MemberShift shift) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat.yMMMd().add_jm();

    final Color statusColor = shift.isOpen
        ? Colors.green
        : (shift.isAutoOut ? Colors.orange : theme.colorScheme.primary);

    final String statusLabel = shift.isOpen
        ? 'Active'
        : (shift.isAutoOut ? 'Auto Out' : 'Completed');

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(120)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withAlpha(30),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        statusLabel,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  tooltip: 'Edit Shift',
                  onPressed: () => _showEditShiftDialog(shift),
                ),
                IconButton(
                  icon: Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: theme.colorScheme.error,
                  ),
                  tooltip: 'Delete Shift',
                  onPressed: () => _showDeleteShiftDialog(shift),
                ),
              ],
            ),
            const Divider(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(Icons.login, size: 20, color: Colors.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Clock In',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      Text(
                        dateFormat.format(shift.clockInTime),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Location: ${shift.clockInLocation}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  Icons.logout,
                  size: 20,
                  color: shift.isOpen ? theme.colorScheme.outline : Colors.red,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Clock Out',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      Text(
                        shift.clockOutTime != null
                            ? dateFormat.format(shift.clockOutTime!)
                            : 'In Progress...',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: shift.isOpen ? theme.colorScheme.outline : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (shift.duration != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Duration: ${_formatDuration(shift.duration!)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _repairTimeline() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Repair Timeline?'),
          content: const Text(
            'This will re-order all log events chronologically, remove duplicate or orphan events, '
            'auto-close unclosed check-ins, and clean up bad data in Google Sheets.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.auto_fix_high),
              label: const Text('Repair'),
            ),
          ],
        );
      },
    );

    if (confirm != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;

    setState(() {
      _isLoading = true;
    });

    try {
      final result = await _timelineManager.repairMemberTimeline(widget.member.id);
      messenger.showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: result.repaired ? Colors.green : null,
        ),
      );
      _loadTimeline();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to repair timeline: $e'),
          backgroundColor: errorColor,
        ),
      );
      setState(() {
        _isLoading = false;
      });
    }
  }

  Widget _buildTimelineSection() {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  "Shifts",
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: _showAddShiftDialog,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Shift'),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.auto_fix_high, size: 20),
                  tooltip: 'Repair Timeline',
                  onPressed: _repairTimeline,
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  tooltip: 'Refresh Timeline',
                  onPressed: _loadTimeline,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(24.0),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Icon(Icons.error_outline, color: theme.colorScheme.error, size: 36),
                    const SizedBox(height: 8),
                    Text(
                      'Failed to load timeline',
                      style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(_errorMessage!, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: _loadTimeline, child: const Text('Retry')),
                  ],
                ),
              )
            else if (_shifts == null || _shifts!.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    Icon(Icons.history_toggle_off, size: 48, color: theme.colorScheme.outline),
                    const SizedBox(height: 8),
                    const Text('No shift history recorded yet for this member.'),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _showAddShiftDialog,
                      icon: const Icon(Icons.add),
                      label: const Text('Add Shift'),
                    ),
                  ],
                ),
              )
            else
              Column(
                children: _shifts!
                    .map((shift) => _buildShiftCard(shift))
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemberInfo(Member member) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: _buildAvatar(member)),
        const SizedBox(height: 16),
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
        const SizedBox(height: 16),
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
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Member Details")),
      body: ValueListenableBuilder<List<Member>>(
        valueListenable: widget.backend.attendance,
        builder: (context, attendanceValue, child) {
          final Member member = attendanceValue.firstWhere(
            (m) => m.id == widget.member.id,
            orElse: () => widget.member,
          );

          return OrientationBuilder(
            builder: (context, orientation) {
              if (orientation == Orientation.landscape) {
                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          child: _buildMemberInfo(member),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: SingleChildScrollView(
                          child: _buildTimelineSection(),
                        ),
                      ),
                    ],
                  ),
                );
              }

              return SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildMemberInfo(member),
                      const SizedBox(height: 16),
                      _buildTimelineSection(),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
