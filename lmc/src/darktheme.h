/****************************************************************************
**
** This file is part of LAN Messenger.
**
** Copyright (c) 2010 - 2012 Qualia Digital Solutions.
**
** Contact:  qualiatech@gmail.com
**
** LAN Messenger is free software: you can redistribute it and/or modify
** it under the terms of the GNU General Public License as published by
** the Free Software Foundation, either version 3 of the License, or
** (at your option) any later version.
**
** LAN Messenger is distributed in the hope that it will be useful,
** but WITHOUT ANY WARRANTY; without even the implied warranty of
** MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
** GNU General Public License for more details.
**
** You should have received a copy of the GNU General Public License
** along with LAN Messenger.  If not, see <http://www.gnu.org/licenses/>.
**
****************************************************************************/

#ifndef DARKTHEME_H
#define DARKTHEME_H

#include <QString>

static const QString DARK_THEME_QSS = QStringLiteral(R"(
    /* ============================================================
       DISCORD-STYLE DARK THEME for LAN Messenger
       ============================================================ */

    /* --- Global --- */
    QWidget {
        background-color: #36393f;
        color: #dcddde;
        font-family: "Segoe UI", "Helvetica Neue", "Arial", sans-serif;
    }

    /* --- Main Window (frameless, rounded) --- */
    QWidget#MainWindow {
        background-color: #36393f;
    }

    /* --- Custom Title Bar (merged with menu bar) --- */
    QWidget#titleBar {
        background-color: #202225;
        border-top-left-radius: 8px;
        border-top-right-radius: 8px;
        min-height: 32px;
        max-height: 32px;
    }
    QLabel#lblTitle {
        color: #ffffff;
        font-weight: 600;
        font-size: 10pt;
        background-color: transparent;
        padding: 0px 4px;
        margin: 0px;
        min-height: 32px;
        max-height: 32px;
    }
    QLabel#lblAppIcon {
        background-color: transparent;
        padding: 0px;
        margin: 0px;
    }

    /* --- Nav buttons: fixed 32x32 (square, 1:1) --- */
    QToolButton#btnTitleMinimize,
    QToolButton#btnTitleMaximize,
    QToolButton#btnTitleClose {
        background-color: transparent;
        color: #b9bbbe;
        border: none;
        border-radius: 0px;
        padding: 0px;
        margin: 0px;
        min-width: 32px;
        max-width: 32px;
        min-height: 32px;
        max-height: 32px;
    }
    QToolButton#btnTitleMinimize:hover,
    QToolButton#btnTitleMaximize:hover {
        background-color: #393c43;
    }
    QToolButton#btnTitleClose:hover {
        background-color: #ed4245;
    }
    QToolButton#btnTitleMinimize:pressed,
    QToolButton#btnTitleMaximize:pressed {
        background-color: #4f545c;
    }
    QToolButton#btnTitleClose:pressed {
        background-color: #c03537;
    }

    /* --- Main Window / Chat Window / Dialogs --- */
    QWidget#ChatWindow,
    QWidget#ChatRoomWindow,
    QWidget#BroadcastWindow,
    QDialog,
    QWidget#SettingsDialog {
        background-color: #36393f;
    }

    /* --- Top Frame (user info bar) --- */
    QFrame#frame {
        background-color: #2f3136;
        border-bottom: 1px solid #202225;
    }

    /* --- Labels --- */
    QLabel {
        background-color: transparent;
        color: #dcddde;
        border: none;
    }
    QLabel#lblUserName {
        color: #ffffff;
        font-weight: bold;
    }
    QLabel#lblDividerTop {
        background-color: #202225;
    }

    /* --- Line Edit (note input) --- */
    QLineEdit, lmcLineEdit {
        background-color: #40444b;
        color: #dcddde;
        border: 1px solid #202225;
        border-radius: 4px;
        padding: 2px 6px;
        selection-background-color: #5865f2;
    }
    QLineEdit:focus, lmcLineEdit:focus {
        border-color: #5865f2;
    }

    /* --- Text Edit (message input) --- */
    QTextEdit {
        background-color: #40444b;
        color: #dcddde;
        border: 1px solid #202225;
        border-radius: 6px;
        padding: 6px 8px;
        selection-background-color: #5865f2;
        font-size: 10pt;
    }
    QTextEdit:focus {
        border-color: #5865f2;
    }

    /* --- Text Browser (message log) --- */
    QTextBrowser {
        background-color: #36393f;
        color: #dcddde;
        border: none;
    }

    /* --- Tree Widget (user list) --- */
    QTreeWidget {
        background-color: #2f3136;
        color: #dcddde;
        border: none;
        outline: none;
    }
    QTreeWidget::item {
        padding: 2px 4px;
        min-height: 28px;
    }
    QTreeWidget::item:selected {
        background-color: #393c43;
    }
    QTreeWidget::item:hover {
        background-color: #32353b;
    }

    /* --- Header View (tree header) --- */
    QHeaderView {
        background-color: #2f3136;
    }
    QHeaderView::section {
        background-color: #2f3136;
        color: #8e9297;
        border: none;
        padding: 2px;
    }

    /* --- Menu Bar (in title bar — transparent, no border) --- */
    QMenuBar {
        background-color: transparent;
        color: #b9bbbe;
        border: none;
        padding: 0px;
        margin: 0px;
        font-size: 9pt;
    }
    QMenuBar::item {
        background-color: transparent;
        color: #b9bbbe;
        padding: 6px 10px;
        border-radius: 4px;
        margin: 0px;
    }
    QMenuBar::item:selected {
        background-color: #393c43;
        color: #dcddde;
    }
    QMenuBar::item:pressed {
        background-color: #2f3136;
        color: #ffffff;
    }

    /* --- Menus --- */
    QMenu {
        background-color: #2f3136;
        color: #dcddde;
        border: 1px solid #202225;
        border-radius: 6px;
        padding: 4px;
    }
    QMenu::item {
        padding: 6px 32px 6px 12px;
        border-radius: 4px;
    }
    QMenu::item:selected {
        background-color: #393c43;
    }
    QMenu::separator {
        height: 1px;
        background-color: #40444b;
        margin: 4px 8px;
    }
    QMenu::indicator {
        margin-left: 4px;
    }

    /* --- Tool Bar --- */
    QToolBar {
        background-color: transparent;
        border: none;
        spacing: 2px;
        padding: 2px;
    }
    QToolBar#pStatusBar {
        background-color: transparent;
    }

    /* --- Tool Buttons --- */
    QToolButton {
        background-color: transparent;
        color: #b9bbbe;
        border: none;
        border-radius: 4px;
        padding: 4px;
    }
    QToolButton:hover {
        background-color: #393c43;
        color: #dcddde;
    }
    QToolButton:pressed {
        background-color: #4f545c;
    }
    QToolButton:checked {
        background-color: #393c43;
        color: #ffffff;
    }
    QToolButton#btnAvatar {
        border: 2px solid transparent;
        border-radius: 2px;
        padding: 0px;
        margin: 0px;
    }
    QToolButton#btnAvatar:hover {
        background-color: #393c43;
        border-color: #5865f2;
    }
    QToolButton#btnAvatar:pressed {
        background-color: #2f3136;
    }

    /* --- Status Button (1:1 square, whole-box hover, no arrow) --- */
    QToolButton#btnStatus {
        background-color: transparent;
        color: #dcddde;
        border: none;
        border-radius: 4px;
        padding: 2px;
        margin: 0px;
    }
    QToolButton#btnStatus:hover {
        background-color: #393c43;
        color: #ffffff;
    }
    QToolButton#btnStatus:pressed {
        background-color: #2f3136;
    }
    QToolButton#btnStatus::menu-indicator {
        image: none;
        width: 0px;
    }

    /* --- Status Popup Menu --- */
    QMenu#statusMenu {
        background-color: #2f3136;
        color: #dcddde;
        border: 1px solid #202225;
        border-radius: 4px;
        padding: 4px;
    }
    QMenu#statusMenu::item {
        padding: 6px 12px 6px 28px;
        border-radius: 4px;
    }
    QMenu#statusMenu::item:selected {
        background-color: #393c43;
        color: #ffffff;
    }
    QMenu#statusMenu::indicator {
        width: 16px;
        height: 16px;
        margin-left: 4px;
    }

    /* --- Push Buttons --- */
    QPushButton {
        background-color: #4f545c;
        color: #ffffff;
        border: none;
        border-radius: 4px;
        padding: 6px 16px;
        font-size: 10pt;
        min-height: 24px;
    }
    QPushButton:hover {
        background-color: #5d6269;
    }
    QPushButton:pressed {
        background-color: #686d73;
    }
    QPushButton:disabled {
        background-color: #3e4148;
        color: #6a6d73;
    }
    QPushButton#btnAddBroadcast,
    QPushButton#btnDeleteBroadcast {
        min-height: 20px;
        padding: 3px 12px;
    }

    /* --- Combo Box --- */
    QComboBox {
        background-color: #40444b;
        color: #dcddde;
        border: 1px solid #202225;
        border-radius: 4px;
        padding: 4px 8px;
        min-height: 20px;
    }
    QComboBox:hover {
        border-color: #5865f2;
    }
    QComboBox::drop-down {
        border: none;
        width: 24px;
    }
    QComboBox::down-arrow {
        image: none;
        border: solid #b9bbbe;
        border-width: 0 2px 2px 0;
        padding: 3px;
        transform: rotate(45deg);
    }
    QComboBox QAbstractItemView {
        background-color: #2f3136;
        color: #dcddde;
        border: 1px solid #202225;
        border-radius: 4px;
        selection-background-color: #393c43;
        outline: none;
    }

    /* --- Spin Box --- */
    QSpinBox {
        background-color: #40444b;
        color: #dcddde;
        border: 1px solid #202225;
        border-radius: 4px;
        padding: 4px;
        min-height: 20px;
    }
    QSpinBox:focus {
        border-color: #5865f2;
    }
    QSpinBox::up-button, QSpinBox::down-button {
        border: none;
        background: transparent;
        width: 20px;
    }

    /* --- Check Box & Radio Button --- */
    QCheckBox {
        color: #dcddde;
        spacing: 8px;
    }
    QCheckBox::indicator {
        width: 16px;
        height: 16px;
        border: 2px solid #72767d;
        border-radius: 3px;
        background-color: transparent;
    }
    QCheckBox::indicator:checked {
        background-color: #5865f2;
        border-color: #5865f2;
    }
    QCheckBox::indicator:hover {
        border-color: #8e9297;
    }

    QRadioButton {
        color: #dcddde;
        spacing: 8px;
    }
    QRadioButton::indicator {
        width: 16px;
        height: 16px;
        border: 2px solid #72767d;
        border-radius: 10px;
        background-color: transparent;
    }
    QRadioButton::indicator:checked {
        background-color: #5865f2;
        border-color: #5865f2;
    }

    /* --- Group Box --- */
    QGroupBox {
        color: #dcddde;
        border: 1px solid #40444b;
        border-radius: 6px;
        margin-top: 12px;
        padding: 16px 12px 12px 12px;
        font-weight: bold;
    }
    QGroupBox::title {
        subcontrol-origin: margin;
        padding: 0 8px;
        color: #8e9297;
    }

    /* --- Tab Widget --- */
    QTabWidget::pane {
        background-color: #2f3136;
        border: 1px solid #202225;
        border-radius: 4px;
    }
    QTabBar::tab {
        background-color: #2f3136;
        color: #8e9297;
        border: none;
        padding: 8px 16px;
        border-top-left-radius: 4px;
        border-top-right-radius: 4px;
    }
    QTabBar::tab:selected {
        background-color: #36393f;
        color: #ffffff;
        border-bottom: 2px solid #5865f2;
    }
    QTabBar::tab:hover {
        color: #dcddde;
    }

    /* --- List Widget --- */
    QListWidget {
        background-color: #2f3136;
        color: #dcddde;
        border: 1px solid #202225;
        border-radius: 4px;
        outline: none;
    }
    QListWidget::item {
        padding: 4px 8px;
        border-radius: 4px;
    }
    QListWidget::item:selected {
        background-color: #393c43;
    }
    QListWidget::item:hover {
        background-color: #32353b;
    }

    /* --- Table Widget --- */
    QTableWidget {
        background-color: #2f3136;
        color: #dcddde;
        border: 1px solid #202225;
        gridline-color: #40444b;
    }
    QTableWidget::item {
        padding: 4px;
    }
    QTableWidget::item:selected {
        background-color: #393c43;
    }
    QHeaderView::section {
        background-color: #2f3136;
        color: #8e9297;
        border: none;
        border-bottom: 1px solid #40444b;
        padding: 4px;
    }

    /* --- Scroll Bars --- */
    QScrollBar:vertical {
        background-color: #2f3136;
        width: 8px;
        margin: 0;
        border: none;
    }
    QScrollBar::handle:vertical {
        background-color: #202225;
        min-height: 30px;
        border-radius: 4px;
    }
    QScrollBar::handle:vertical:hover {
        background-color: #40444b;
    }
    QScrollBar::add-line:vertical,
    QScrollBar::sub-line:vertical {
        height: 0;
        border: none;
    }
    QScrollBar::add-page:vertical,
    QScrollBar::sub-page:vertical {
        background: none;
    }

    QScrollBar:horizontal {
        background-color: #2f3136;
        height: 8px;
        margin: 0;
        border: none;
    }
    QScrollBar::handle:horizontal {
        background-color: #202225;
        min-width: 30px;
        border-radius: 4px;
    }
    QScrollBar::handle:horizontal:hover {
        background-color: #40444b;
    }
    QScrollBar::add-line:horizontal,
    QScrollBar::sub-line:horizontal {
        width: 0;
        border: none;
    }
    QScrollBar::add-page:horizontal,
    QScrollBar::sub-page:horizontal {
        background: none;
    }

    /* --- Splitter --- */
    QSplitter::handle {
        background-color: #2f3136;
    }
    QSplitter::handle:hover {
        background-color: #5865f2;
    }
    QSplitter::handle:vertical {
        height: 2px;
    }
    QSplitter::handle:horizontal {
        width: 2px;
    }

    /* --- Progress Bar --- */
    QProgressBar {
        background-color: #40444b;
        border: 1px solid #202225;
        border-radius: 4px;
        text-align: center;
        color: #dcddde;
        height: 20px;
    }
    QProgressBar::chunk {
        background-color: #5865f2;
        border-radius: 3px;
    }

    /* --- Tool Tip --- */
    QToolTip {
        background-color: #202225;
        color: #dcddde;
        border: 1px solid #40444b;
        border-radius: 4px;
        padding: 4px 8px;
        font-size: 9pt;
    }

    /* --- Dialog button box --- */
    QDialogButtonBox QPushButton {
        min-width: 80px;
    }

    /* --- Scroll Area --- */
    QScrollArea {
        background-color: transparent;
        border: none;
    }

    /* --- Info label in chat --- */
    QLabel#lblInfo {
        color: #8e9297;
        background-color: #2f3136;
        border-top: 1px solid #202225;
        border-bottom: 1px solid #202225;
        padding: 2px 8px;
        font-size: 9pt;
    }

    /* --- Tree widget in history --- */
    QTreeWidget#tvMsgList {
        background-color: #2f3136;
    }
    QTreeWidget#tvMsgList::item {
        min-height: 24px;
    }
)");

#endif // DARKTHEME_H
