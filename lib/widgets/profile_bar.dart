import 'package:fluent_ui/fluent_ui.dart';
import '../models/audio_models.dart';
import '../theme/app_theme.dart';
import '../platform.dart';

/// Horizontal profile selector chips with add/save button.
class ProfileBar extends StatelessWidget {
  final List<RoutingProfile> profiles;
  final String? activeProfileId;
  final ValueChanged<String> onProfileTap;
  final VoidCallback? onSaveProfile;
  final ValueChanged<String>? onDeleteProfile;
  final ValueChanged<String>? onEditProfile;

  const ProfileBar({
    super.key,
    required this.profiles,
    required this.activeProfileId,
    required this.onProfileTap,
    this.onSaveProfile,
    this.onDeleteProfile,
    this.onEditProfile,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          ...profiles.asMap().entries.map((entry) {
            final index = entry.key;
            final profile = entry.value;
            final isActive = profile.id == activeProfileId;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _ProfileChip(
                profile: profile,
                isActive: isActive,
                onTap: () => onProfileTap(profile.id),
                onLongPress: () => onEditProfile?.call(profile.id),
                onDelete: () => onDeleteProfile?.call(profile.id),
                hotkeyIndex: index < 9 ? index : null,
              ),
            );
          }),
          if (onSaveProfile != null)
            _AddProfileButton(onTap: onSaveProfile!),
        ],
      ),
    );
  }
}

class _AddProfileButton extends StatefulWidget {
  final VoidCallback onTap;
  const _AddProfileButton({required this.onTap});

  @override
  State<_AddProfileButton> createState() => _AddProfileButtonState();
}

class _AddProfileButtonState extends State<_AddProfileButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          padding: EdgeInsets.symmetric(
            horizontal: 8,
            vertical: isMacOS ? 6 : 5,
          ),
          decoration: BoxDecoration(
            color: _isHovered ? AppColors.bgHover : Colors.transparent,
            borderRadius: BorderRadius.circular(AppColors.cardRadius),
            border: Border.all(
              color: _isHovered ? AppColors.borderHover : AppColors.border,
              width: 0.5,
            ),
          ),
          child: Text(
            '+',
            style: AppTheme.inter(
              fontSize: 13,
              color: _isHovered ? AppColors.textSecondary : AppColors.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileChip extends StatefulWidget {
  final RoutingProfile profile;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDelete;
  final int? hotkeyIndex;

  const _ProfileChip({
    required this.profile,
    required this.isActive,
    required this.onTap,
    this.onLongPress,
    this.onDelete,
    this.hotkeyIndex,
  });

  @override
  State<_ProfileChip> createState() => _ProfileChipState();
}

class _ProfileChipState extends State<_ProfileChip> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: EdgeInsets.symmetric(
            horizontal: isMacOS ? 11 : 10,
            vertical: isMacOS ? 6 : 5,
          ),
          decoration: BoxDecoration(
            color: widget.isActive
                ? AppColors.accent.withValues(alpha: isDarkTheme ? 0.12 : 0.08)
                : _isHovered
                    ? AppColors.bgHover
                    : isDarkTheme
                        ? Colors.transparent
                        : AppColors.bgSecondary,
            borderRadius: BorderRadius.circular(AppColors.cardRadius),
            border: Border.all(
              color: widget.isActive
                  ? AppColors.accent.withValues(alpha: isDarkTheme ? 0.3 : 0.4)
                  : _isHovered
                      ? AppColors.borderHover
                      : AppColors.border,
              width: 0.5,
            ),
            boxShadow: !isDarkTheme && widget.isActive
                ? [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.profile.icon,
                style: AppTheme.inter(fontSize: 12),
              ),
              const SizedBox(width: 5),
              Text(
                widget.profile.name,
                style: AppTheme.inter(
                  fontSize: 11,
                  fontWeight: widget.isActive ? FontWeight.w600 : FontWeight.w400,
                  color: widget.isActive
                      ? AppColors.accent
                      : AppColors.textSecondary,
                ),
              ),
              if (widget.hotkeyIndex != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.bgTertiary,
                    borderRadius: BorderRadius.circular(isMacOS ? 4 : 3),
                    border: Border.all(
                      color: AppColors.border,
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    '$hotkeyModifierSymbol+${widget.hotkeyIndex! + 1}',
                    style: AppTheme.inter(
                      fontSize: 9,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
