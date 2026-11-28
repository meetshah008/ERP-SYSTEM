import 'package:flutter/material.dart';
import '../../core/network/session_manager.dart';
import 'finance_screen.dart';
import 'bank_expenses/quick_bank_expense_tab.dart';
import 'salary_templates/salary_templates_screen.dart';
import 'salary_components/salary_components_screen.dart';

class FinanceHubScreen extends StatefulWidget {
  const FinanceHubScreen({super.key});

  @override
  State<FinanceHubScreen> createState() => _FinanceHubScreenState();
}

class _FinanceHubScreenState extends State<FinanceHubScreen> {
  String _role = '';
  Map<String, bool> _permissions = {};

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  Future<void> _loadSession() async {
    final session = await SessionManager.getUserSession();
    final perms = await SessionManager.getPermissions();
    if (!mounted) return;
    setState(() {
      _role = (session['role'] ?? '').toString();
      _permissions = perms;
    });
  }

  bool _can(String key) {
    if (_role == 'Super Admin') return true;
    return _permissions[key] ?? false;
  }

  void _openPage(Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  void _comingSoon(String title) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$title module will be added in the next step.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 900;

    final cards = <Widget>[
      _moduleCard(
        icon: Icons.account_balance_wallet_outlined,
        color: Colors.teal,
        title: 'Bank & Expenses',
        subtitle: 'View Cash/Bank balances and record daily expenses',
        badge: 'READY',
        onTap: () => _openPage(
          Scaffold(
            backgroundColor: Colors.white,
            appBar: AppBar(
              title: const Text('Bank & Expenses'),
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              surfaceTintColor: Colors.white,
              elevation: 0,
            ),
            body: QuickBankExpenseTab(
              canAddExpense: _can('finance_create_voucher'),
              onExpenseAdded: () {},
            ),
          ),
        ),
      ),
      _moduleCard(
        icon: Icons.payments_outlined,
        color: Colors.indigo,
        title: 'Salary & Payroll',
        subtitle: 'Auto-calculate payroll from HR salary, attendance, and leaves',
        badge: 'SOON',
        onTap: () => _comingSoon('Salary & Payroll'),
      ),
      _moduleCard(
        icon: Icons.description_outlined,
        color: Colors.green,
        title: 'Client Invoices',
        subtitle: 'Create client bills and record incoming payments',
        badge: 'SOON',
        onTap: () => _comingSoon('Client Invoices'),
      ),
      _moduleCard(
        icon: Icons.local_shipping_outlined,
        color: Colors.orange,
        title: 'Vendor Bills',
        subtitle: 'Track supplier bills and pending payables',
        badge: 'SOON',
        onTap: () => _comingSoon('Vendor Bills'),
      ),
      _moduleCard(
        icon: Icons.account_tree_outlined,
        color: Colors.blueGrey,
        title: 'Advanced Accounting',
        subtitle: 'Ledger, Trial Balance, Vouchers & P&L Reports (CA View)',
        badge: 'FULL',
        onTap: () => _openPage(const FinanceScreen()),
      ),
      _moduleCard(
        icon: Icons.layers_outlined,
        color: Colors.cyan,
        title: 'Salary Templates',
        subtitle: 'Manage & switch employee salary templates in 1 click',
        badge: 'READY',
        onTap: () => _openPage(const SalaryTemplatesScreen()),
      ),
      _moduleCard(
        icon: Icons.tune_outlined,
        color: Colors.purple,
        title: 'Salary Components',
        subtitle: 'Manage earnings, deductions, PF/ESI percentages & custom components',
        badge: 'READY',
        onTap: () => _openPage(const SalaryComponentsScreen()),
      ),
    ];

    if (isMobile) {
      return CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Accounts & Finance',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Select a module to manage your company finances',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
            sliver: SliverGrid.extent(
              maxCrossAxisExtent: 300,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 1.35,
              children: cards,
            ),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Accounts & Finance',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Select a module to manage your company finances',
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: GridView.extent(
              maxCrossAxisExtent: 300,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 1.35,
              children: cards,
            ),
          ),
        ],
      ),
    );
  }

  Widget _moduleCard({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required String badge,
    required VoidCallback onTap,
  }) {
    return _HoverFinanceModuleCard(
      icon: icon,
      color: color,
      title: title,
      subtitle: subtitle,
      badge: badge,
      onTap: onTap,
    );
  }

}

class _HoverFinanceModuleCard extends StatefulWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String badge;
  final VoidCallback onTap;

  const _HoverFinanceModuleCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.onTap,
  });

  @override
  State<_HoverFinanceModuleCard> createState() => _HoverFinanceModuleCardState();
}

class _HoverFinanceModuleCardState extends State<_HoverFinanceModuleCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final cardBorder = isDark ? Colors.white12 : const Color(0xFFE2E8F0);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _hovered ? -3 : 0, 0),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _hovered
                ? widget.color.withValues(alpha: 0.55)
                : cardBorder,
            width: _hovered ? 1.4 : 1.1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: isDark
                    ? (_hovered ? 0.35 : 0.22)
                    : (_hovered ? 0.09 : 0.05),
              ),
              blurRadius: _hovered ? 22 : 14,
              offset: Offset(0, _hovered ? 10 : 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: widget.onTap,
            hoverColor: widget.color.withValues(alpha: 0.03),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      CircleAvatar(
                        backgroundColor: widget.color.withValues(alpha: 0.12),
                        child: Icon(widget.icon, color: widget.color),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: widget.color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          widget.badge,
                          style: TextStyle(
                            color: widget.color,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    widget.title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}