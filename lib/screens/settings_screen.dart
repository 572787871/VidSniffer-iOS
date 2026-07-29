import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/account_service.dart';
import '../services/ui_state.dart';
import '../theme/app_theme.dart';
import '../widgets/apple_ui.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({this.embedded = false, super.key});

  final bool embedded;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final state = UiStateScope.of(context);
    final account = state.accountService;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 76,
        titleSpacing: 24,
        titleTextStyle: Theme.of(context).textTheme.displaySmall,
        automaticallyImplyLeading: !widget.embedded,
        leading: widget.embedded
            ? null
            : CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: Navigator.of(context).pop,
                child: const Icon(CupertinoIcons.back),
              ),
        title: const Text('用户'),
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([state, account]),
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 128),
          children: [
            _AccountHero(
              account: account,
              onApple: () => _appleLogin(account),
              onEmail: () => _showEmailAccountSheet(account),
            ),
            const SizedBox(height: 24),
            const AppleSectionHeader(title: '下载偏好'),
            AppleListGroup(
              footer: '下载任务在后台运行，界面只以低频率刷新进度，减少滚动卡顿。',
              children: [
                ListTile(
                  leading: const AppleIconTile(
                    icon: CupertinoIcons.wifi,
                    color: AppTheme.blue,
                  ),
                  title: const Text('仅 Wi-Fi 下载'),
                  subtitle: const Text('避免使用移动数据下载大文件'),
                  trailing: CupertinoSwitch(
                    value: state.onlyWifi,
                    activeTrackColor: AppTheme.green,
                    onChanged: state.toggleWifi,
                  ),
                  onTap: () => state.toggleWifi(!state.onlyWifi),
                ),
                const AppleListTile(
                  title: '默认保存位置',
                  subtitle: '全部视频',
                  icon: CupertinoIcons.folder_fill,
                  iconColor: AppTheme.orange,
                ),
              ],
            ),
            const SizedBox(height: 22),
            const AppleSectionHeader(title: '浏览与隐私'),
            AppleListGroup(
              children: [
                const AppleListTile(
                  title: '智能解析',
                  subtitle: '静态解析优先，必要时启用隐藏浏览器',
                  icon: CupertinoIcons.link,
                  iconColor: AppTheme.blue,
                ),
                AppleListTile(
                  title: '使用与版权说明',
                  subtitle: '下载内容与隐私保护',
                  icon: CupertinoIcons.hand_raised_fill,
                  iconColor: AppTheme.purple,
                  onTap: () => _showCompliance(context),
                ),
              ],
            ),
            const SizedBox(height: 22),
            const AppleSectionHeader(title: '存储'),
            AppleListGroup(
              children: [
                AppleListTile(
                  title: '清理临时缓存',
                  subtitle: '不会删除已经下载的视频',
                  icon: CupertinoIcons.trash_fill,
                  iconColor: AppTheme.red,
                  onTap: () => _showCacheNotice(context),
                ),
              ],
            ),
            if (account.signedIn) ...[
              const SizedBox(height: 22),
              AppleListGroup(
                children: [
                  ListTile(
                    title: const Text(
                      '退出登录',
                      style: TextStyle(color: AppTheme.red),
                    ),
                    onTap: () => _confirmSignOut(account),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 22),
            const AppleSectionHeader(title: '关于'),
            const AppleListGroup(
              children: [
                ListTile(
                  title: Text('VidSniffer Pro'),
                  subtitle: Text('版本 1.0.0'),
                  trailing: Icon(
                    CupertinoIcons.checkmark_seal_fill,
                    color: AppTheme.blue,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _appleLogin(AccountService account) async {
    try {
      await account.signInWithApple();
    } catch (error) {
      if (mounted) _showError('$error');
    }
  }

  Future<void> _showEmailAccountSheet(AccountService account) async {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final nameController = TextEditingController();
    var registering = false;
    var submitting = false;
    String errorText = '';
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> submit() async {
              final email = emailController.text.trim();
              final password = passwordController.text;
              final name = nameController.text.trim();
              if (!email.contains('@')) {
                setSheetState(() => errorText = '请输入有效邮箱地址');
                return;
              }
              if (password.length < 8) {
                setSheetState(() => errorText = '密码至少需要 8 个字符');
                return;
              }
              if (registering && name.isEmpty) {
                setSheetState(() => errorText = '请输入昵称');
                return;
              }
              setSheetState(() {
                submitting = true;
                errorText = '';
              });
              try {
                if (registering) {
                  await account.registerWithEmail(
                    name: name,
                    email: email,
                    password: password,
                  );
                } else {
                  await account.signInWithEmail(
                    email: email,
                    password: password,
                  );
                }
                if (sheetContext.mounted) Navigator.pop(sheetContext);
              } catch (error) {
                if (sheetContext.mounted) {
                  setSheetState(() => errorText = '$error');
                }
              } finally {
                if (sheetContext.mounted) {
                  setSheetState(() => submitting = false);
                }
              }
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                0,
                20,
                20 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      registering ? '创建账号' : '邮箱登录',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      registering
                          ? '注册后可在不同设备恢复个人设置。'
                          : '使用已注册的邮箱继续。',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (registering) ...[
                      TextField(
                        controller: nameController,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.name],
                        decoration: const InputDecoration(
                          labelText: '昵称',
                          prefixIcon: Icon(CupertinoIcons.person),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: '邮箱',
                        prefixIcon: Icon(CupertinoIcons.mail),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      autofillHints: [
                        registering
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      onSubmitted: (_) => submit(),
                      decoration: const InputDecoration(
                        labelText: '密码',
                        prefixIcon: Icon(CupertinoIcons.lock),
                      ),
                    ),
                    if (errorText.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        errorText,
                        style: const TextStyle(
                          color: AppTheme.red,
                          fontSize: 13,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: submitting ? null : submit,
                        child: submitting
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CupertinoActivityIndicator(
                                  color: Colors.white,
                                ),
                              )
                            : Text(registering ? '注册并登录' : '登录'),
                      ),
                    ),
                    Center(
                      child: CupertinoButton(
                        onPressed: submitting
                            ? null
                            : () => setSheetState(() {
                                registering = !registering;
                                errorText = '';
                              }),
                        child: Text(
                          registering ? '已有账号？登录' : '没有账号？注册',
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
    } finally {
      emailController.dispose();
      passwordController.dispose();
      nameController.dispose();
    }
  }

  Future<void> _confirmSignOut(AccountService account) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('退出登录？'),
        content: const Text('\n已下载的视频不会被删除。'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirmed == true) await account.signOut();
  }

  void _showError(String message) {
    showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('无法登录'),
        content: Text('\n$message'),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: Navigator.of(context).pop,
            child: const Text('好'),
          ),
        ],
      ),
    );
  }

  static void _showCacheNotice(BuildContext context) {
    showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('清理临时缓存'),
        content: const Text('\n当前没有需要清理的临时缓存。已下载视频不会被删除。'),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: Navigator.of(context).pop,
            child: const Text('好'),
          ),
        ],
      ),
    );
  }

  static void _showCompliance(BuildContext context) {
    showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('使用与版权说明'),
        content: const Text(
          '\n请仅下载自己有权访问和保存的视频。本 App 不绕过 DRM、付费墙或加密版权保护。',
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: Navigator.of(context).pop,
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
  }
}

class _AccountHero extends StatelessWidget {
  const _AccountHero({
    required this.account,
    required this.onApple,
    required this.onEmail,
  });

  final AccountService account;
  final VoidCallback onApple;
  final VoidCallback onEmail;

  @override
  Widget build(BuildContext context) {
    final profile = account.profile;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: AppTheme.blue.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  profile == null
                      ? CupertinoIcons.person_fill
                      : CupertinoIcons.person_crop_circle_fill,
                  color: AppTheme.blue,
                  size: 31,
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile?.displayName ?? '登录 VidSniffer',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.25,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      profile?.email.isNotEmpty == true
                          ? profile!.email
                          : '同步个人设置与文件夹信息',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (profile != null)
                const Icon(
                  CupertinoIcons.checkmark_seal_fill,
                  color: AppTheme.blue,
                ),
            ],
          ),
          if (profile == null) ...[
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: account.loading ? null : onApple,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.apple),
                label: const Text('通过 Apple 登录'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: account.loading ? null : onEmail,
                icon: const Icon(CupertinoIcons.mail),
                label: const Text('邮箱登录或注册'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
