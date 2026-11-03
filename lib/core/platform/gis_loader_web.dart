import 'dart:js_interop';

@JS('abelnotesLoadGis')
external JSFunction? get _loadGis;

/// Lets web/index.html add the sign-in script it held back at launch.
void releaseGoogleSignInScript() => _loadGis?.callAsFunction();
