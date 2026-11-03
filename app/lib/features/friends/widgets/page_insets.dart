import 'package:flutter/material.dart';

import '../../../app/ui/ui.dart';

/// Room under the last item of a scrolling page: 24 px plus the gesture bar
/// or home indicator, which a list with explicit padding no longer gets for
/// free (docs/12 §2). Inside the tab shell the navigation bar has already
/// taken that inset, so this is 24 there.
double pageBottomInset(BuildContext context) =>
    Space.xl + MediaQuery.paddingOf(context).bottom;

/// Bottom padding for a sheet body: the keyboard while it is up. The gesture
/// bar or home indicator is already cleared by `showDrivalrySheet` itself.
EdgeInsets sheetBottomInset(BuildContext context) =>
    EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom);
