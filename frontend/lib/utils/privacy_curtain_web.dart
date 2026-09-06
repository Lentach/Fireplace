import 'dart:js_interop';

@JS('__fpCurtain')
external _FpCurtain? get _curtain;

extension type _FpCurtain._(JSObject _) implements JSObject {
  external void arm(JSBoolean on);
  external void show();
  external void hide();
}

void armDomCurtain(bool enabled) => _curtain?.arm(enabled.toJS);

void showDomCurtain() => _curtain?.show();

void hideDomCurtain() => _curtain?.hide();
