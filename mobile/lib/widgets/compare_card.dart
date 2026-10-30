import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// 全网智能比价直达卡片组件
class CompareCard extends StatelessWidget {
  final String keyword;

  const CompareCard({super.key, required this.keyword});

  Future<void> _openPlatform(BuildContext context, {
    required String name,
    required String appScheme,
    required String webUrl,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final appUri = Uri.parse(appScheme);
      final canLaunchApp = await canLaunchUrl(appUri);
      if (canLaunchApp) {
        await launchUrl(appUri, mode: LaunchMode.externalNonBrowserApplication);
        return;
      }
    } catch (_) {}

    // 唤起 App 失败时降级到系统浏览器
    try {
      final webUri = Uri.parse(webUrl);
      if (await canLaunchUrl(webUri)) {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      } else {
        messenger.showSnackBar(
          SnackBar(content: Text('无法打开 $name 比价链接，请检查浏览器设置')),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('打开失败：$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final encoded = Uri.encodeComponent(keyword);

    final platforms = [
      _PlatformItem(
        name: '拼多多',
        badge: '百亿补贴底价',
        color: const Color(0xFFE02E24),
        icon: Icons.local_mall_rounded,
        appScheme: 'pinduoduo://search_result.html?search_key=$encoded',
        webUrl: 'https://mobile.yangkeduo.com/search_result.html?search_key=$encoded',
      ),
      _PlatformItem(
        name: '手机淘宝',
        badge: '官方正品比价',
        color: const Color(0xFFFF5000),
        icon: Icons.shopping_bag_rounded,
        appScheme: 'taobao://s.taobao.com/search?q=$encoded',
        webUrl: 'https://s.taobao.com/search?q=$encoded',
      ),
      _PlatformItem(
        name: '京东自营',
        badge: '现货自营次日达',
        color: const Color(0xFFE1251B),
        icon: Icons.shopping_cart_rounded,
        appScheme: 'openapp.jdmobile://virtual?params={"category":"jump","des":"productList","keyWord":"$encoded"}',
        webUrl: 'https://search.jd.com/Search?keyword=$encoded',
      ),
      _PlatformItem(
        name: '历史底价',
        badge: '180天价格走势',
        color: const Color(0xFF2563EB),
        icon: Icons.insights_rounded,
        appScheme: 'http://s.manmanbuy.com/m/Default.aspx?keywords=$encoded',
        webUrl: 'http://s.manmanbuy.com/m/Default.aspx?keywords=$encoded',
      ),
    ];

    return Container(
      margin: const EdgeInsets.only(top: 10.0),
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.price_check_rounded, size: 16, color: Color(0xFF8B5CF6)),
              ),
              const SizedBox(width: 8),
              const Text(
                '全网直达比价通道',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  keyword,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: platforms.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 2.5,
            ),
            itemBuilder: (context, index) {
              final p = platforms[index];
              return InkWell(
                onTap: () => _openPlatform(
                  context,
                  name: p.name,
                  appScheme: p.appScheme,
                  webUrl: p.webUrl,
                ),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: p.color.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: p.color.withValues(alpha: 0.2), width: 1),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: p.color,
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Icon(p.icon, size: 14, color: Colors.white),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              p.name,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: p.color,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              p.badge,
                              style: TextStyle(
                                fontSize: 9,
                                color: p.color.withValues(alpha: 0.8),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.arrow_forward_ios_rounded, size: 10, color: p.color.withValues(alpha: 0.6)),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PlatformItem {
  final String name;
  final String badge;
  final Color color;
  final IconData icon;
  final String appScheme;
  final String webUrl;

  const _PlatformItem({
    required this.name,
    required this.badge,
    required this.color,
    required this.icon,
    required this.appScheme,
    required this.webUrl,
  });
}
