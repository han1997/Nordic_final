import 'package:flutter_test/flutter_test.dart';
import 'package:nordic/theme/tokens.dart';

void main() {
  test('深浅两套 token 的亮度标记正确', () {
    expect(NordicTokens.dark.isDark, isTrue);
    expect(NordicTokens.light.isDark, isFalse);
  });

  test('浅色下光晕被压到很低 —— 浅底上发光会脏', () {
    expect(NordicTokens.dark.glow, 1.0);
    expect(NordicTokens.light.glow, lessThan(0.2));
  });

  test('浅色的模糊半径比深色小 —— 浅底上大半径会糊成一片', () {
    expect(NordicTokens.light.blur, lessThan(NordicTokens.dark.blur));
    expect(NordicTokens.light.blurSm, lessThan(NordicTokens.dark.blurSm));
  });

  test('主题切换瞬时换材质,不做插值', () {
    expect(NordicTokens.dark.lerp(NordicTokens.light, 0.2), NordicTokens.dark);
    expect(NordicTokens.dark.lerp(NordicTokens.light, 0.8), NordicTokens.light);
  });
}