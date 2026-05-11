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


#include <QDesktopServices>
#include <QRandomGenerator>
#include <QTimer>
#include <QUrl>
#include <QFontDialog>
#include <QColorDialog>
#include <QMimeData>
#include <QFileInfo>
#include <QTextBlock>
#include <QRegularExpression>
#include <QFont>
#include <QColor>
#include <QTreeWidgetItemIterator>
#include "mainwindow.h"
#include "messagelog.h"
#include "history.h"

lmcMainWindow::lmcMainWindow(QWidget *parent, Qt::WindowFlags flags) : QWidget(parent, flags) {
	setWindowFlag(Qt::FramelessWindowHint);
	ui.setupUi(this);

	setStyleSheet(
		"QScrollBar:vertical {"
		"  background: #2f3136;"
		"  width: 8px;"
		"  margin: 0px;"
		"  border-radius: 4px;"
		"}"
		"QScrollBar::handle:vertical {"
		"  background: #40444b;"
		"  min-height: 30px;"
		"  border-radius: 4px;"
		"}"
		"QScrollBar::handle:vertical:hover {"
		"  background: #4f545c;"
		"}"
		"QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {"
		"  height: 0px;"
		"}"
		"QScrollBar::add-page:vertical, QScrollBar::sub-page:vertical {"
		"  background: none;"
		"}"
		"QScrollBar:horizontal {"
		"  background: #2f3136;"
		"  height: 8px;"
		"  margin: 0px;"
		"  border-radius: 4px;"
		"}"
		"QScrollBar::handle:horizontal {"
		"  background: #40444b;"
		"  min-width: 30px;"
		"  border-radius: 4px;"
		"}"
		"QScrollBar::handle:horizontal:hover {"
		"  background: #4f545c;"
		"}"
		"QScrollBar::add-line:horizontal, QScrollBar::sub-line:horizontal {"
		"  width: 0px;"
		"}"
		"QScrollBar::add-page:horizontal, QScrollBar::sub-page:horizontal {"
		"  background: none;"
		"}"
	);

	// Set app icon on title bar (BISCOM logo)
	ui.lblAppIcon->setPixmap(QPixmap(IDR_BISCOM_APP).scaled(20, 20, Qt::KeepAspectRatio, Qt::SmoothTransformation));
	ui.lblAppIcon->setCursor(Qt::PointingHandCursor);
	ui.lblTitle->setText(QStringLiteral("BISCOM Lan Messenger"));

	// Set nav button icons from Assets
	ui.btnTitleMinimize->setIcon(QIcon(QPixmap(IDR_NAV_MINIMIZE)));
	ui.btnTitleMaximize->setIcon(QIcon(QPixmap(IDR_NAV_RESTORE)));
	ui.btnTitleClose->setIcon(QIcon(QPixmap(IDR_NAV_CLOSE)));

	connect(ui.tvUserList, SIGNAL(itemActivated(QTreeWidgetItem*, int)), 
		this, SLOT(tvUserList_itemActivated(QTreeWidgetItem*, int)));
    connect(ui.tvUserList, SIGNAL(itemContextMenu(QTreeWidgetItem*, QPoint&)),
        this, SLOT(tvUserList_itemContextMenu(QTreeWidgetItem*, QPoint&)));
	connect(ui.tvUserList, SIGNAL(itemDragDropped(QTreeWidgetItem*)),
		this, SLOT(tvUserList_itemDragDropped(QTreeWidgetItem*)));
	connect(ui.tvUserList, SIGNAL(currentItemChanged(QTreeWidgetItem*,QTreeWidgetItem*)),
		this, SLOT(tvUserList_currentItemChanged(QTreeWidgetItem*,QTreeWidgetItem*)));
	connect(ui.txtNote, SIGNAL(returnPressed()), this, SLOT(txtNote_returnPressed()));
	connect(ui.txtNote, SIGNAL(lostFocus()), this, SLOT(txtNote_lostFocus()));

	connect(ui.btnTitleMinimize, SIGNAL(clicked()), this, SLOT(titleBarMinimize_clicked()));
	connect(ui.btnTitleMaximize, SIGNAL(clicked()), this, SLOT(titleBarMaximize_clicked()));
	connect(ui.btnTitleClose, SIGNAL(clicked()), this, SLOT(titleBarClose_clicked()));

	// Center status icon and avatar vertically in the header
	ui.horizontalLayout_2->setAlignment(ui.statusLayout, Qt::AlignVCenter);
	ui.horizontalLayout_2->setAlignment(ui.infoLayout, Qt::AlignVCenter);
	ui.horizontalLayout_2->setAlignment(ui.btnAvatar, Qt::AlignVCenter);

    ui.txtNote->installEventFilter(this);
    ui.tvUserList->installEventFilter(this);

	initInlineChat();

	titleBarDrag = false;
	windowLoaded = false;

	// Default to empty page
	ui.rightPanel->setCurrentIndex(0);
}

lmcMainWindow::~lmcMainWindow(void) {
}

void lmcMainWindow::init(User* pLocalUser, QList<Group>* pGroupList, bool connected) {
	setWindowIcon(QIcon(IDR_APPICON));

	this->pLocalUser = pLocalUser;

	createMainMenu();
	createToolBar();
	createStatusMenu();
	createAvatarMenu();

	createTrayMenu();
	createTrayIcon();
	connectionStateChanged(connected);

	createGroupMenu();
	createUserMenu();

	ui.leftPanelLayout->setContentsMargins(5, 0, 5, 5);
	ui.tvUserList->setFocusPolicy(Qt::NoFocus);
	ui.tvUserList->setStyleSheet(
		"lmcUserTreeWidget { background: #2f3136; border-radius: 2px; }"
		"lmcUserTreeWidget::item:focus { outline: none; }"
	);

	ui.frame->setStyleSheet("QFrame { background: #2f3136; border-radius: 2px; }");
	QHBoxLayout* frameLayout = qobject_cast<QHBoxLayout*>(ui.frame->layout());
	if(frameLayout) {
		QSpacerItem* spacer1 = frameLayout->takeAt(0)->spacerItem();
		QLayoutItem* statusItem = frameLayout->takeAt(0);
		QSpacerItem* spacer2 = frameLayout->takeAt(0)->spacerItem();
		QLayoutItem* infoItem = frameLayout->takeAt(0);
		QSpacerItem* spacer3 = frameLayout->takeAt(0)->spacerItem();
		QLayoutItem* avatarItem = frameLayout->takeAt(0);

		frameLayout->addItem(spacer1);
		frameLayout->addItem(avatarItem);
		frameLayout->addItem(spacer2);
		frameLayout->addItem(infoItem);
		frameLayout->addItem(spacer3);
		frameLayout->addItem(statusItem);
	}
	ui.btnAvatar->setFixedSize(40, 40);
	ui.btnAvatar->setIconSize(QSize(32, 32));
	ui.btnAvatar->setStyleSheet(
		"lmcToolButton { border-radius: 2px; }"
		"lmcToolButton::menu-indicator { image: none; }"
	);
	ui.txtNote->setStyleSheet(
		"QLineEdit { border: none; background: transparent; padding: 0px; margin: 0px; }"
	);

	ui.lblDividerTop->setBackgroundRole(QPalette::Highlight);
	ui.lblDividerTop->setAutoFillBackground(true);

	ui.tvUserList->setIconSize(QSize(16, 16));
    ui.tvUserList->header()->setSectionsMovable(false);
	ui.tvUserList->header()->setStretchLastSection(false);
    ui.tvUserList->header()->setSectionResizeMode(0, QHeaderView::Stretch);
	int index = Helper::statusIndexFromCode(pLocalUser->status);
	//	if status is not recognized, default to available
	index = qMax(index, 0);
	btnStatus->setIcon(QIcon(QPixmap(statusPic[index], "PNG")));
	statusGroup->actions()[index]->setChecked(true);
    QFont font = ui.lblUserName->font();
	int fontSize = ui.lblUserName->fontInfo().pixelSize();
	fontSize += (fontSize * 0.1);
	font.setPixelSize(fontSize);
    font.setBold(true);
    ui.lblUserName->setFont(font);
	ui.lblStatus->setText(statusGroup->checkedAction()->text());
	nAvatar = pLocalUser->avatar;
	ui.txtNote->setText(pLocalUser->note);

	pSoundPlayer = new lmcSoundPlayer();
	pSettings = new lmcSettings();
	restoreGeometry(pSettings->value(IDS_WINDOWMAIN).toByteArray());
	//	get saved settings
	settingsChanged(true);
	setUIText();

	initGroups(pGroupList);

	// Restore splitter sizes (roughly 280px left, rest right)
	QList<int> sizes;
	sizes.append(280);
	sizes.append(width() - 280);
	ui.splitter->setSizes(sizes);
}

void lmcMainWindow::start(void) {
	//	if no avatar is set, select a random avatar (useful when running for the first time)
	if(nAvatar > AVT_COUNT) {
		nAvatar = QRandomGenerator::global()->bounded(AVT_COUNT);
	}
	// This method should only be called from here, otherwise an MT_Notify message is sent
	// and the program will connect to the network before start() is called.
	setAvatar();
	pTrayIcon->setVisible(showSysTray);
	if(pSettings->value(IDS_AUTOSHOW, IDS_AUTOSHOW_VAL).toBool())
		show();
}

void lmcMainWindow::show(void) {
	windowLoaded = true;
	QWidget::show();
}

void lmcMainWindow::restore(void) {
	//	if window is minimized, restore it to previous state
	if(windowState().testFlag(Qt::WindowMinimized))
		setWindowState(windowState() & ~Qt::WindowMinimized);
	setWindowState(windowState() | Qt::WindowActive);
	raise();	// make main window the top most window of the application
	show();
	activateWindow();	// bring window to foreground
}

void lmcMainWindow::minimize(void) {
	// This function actually hides the window, basically the opposite of restore()
	hide();
	showMinimizeMessage();
}

void lmcMainWindow::stop(void) {
	//	These settings are saved only if the window was opened at least once by the user
	if(windowLoaded) {
		pSettings->setValue(IDS_WINDOWMAIN, saveGeometry());
		pSettings->setValue(IDS_MINIMIZEMSG, showMinimizeMsg, IDS_MINIMIZEMSG_VAL);
	}

	// Save inline chat message log if there's data
	if(pInlineMessageLog && pInlineMessageLog->hasData && !currentChatPeer.isEmpty()) {
		// Save to cache file for next session
		QString cacheFile = QDir(StdLocation::cacheDir()).absoluteFilePath("msg_" + currentChatPeer + ".tmp");
		pInlineMessageLog->saveMessageLog(cacheFile);
		// Save to history database
		bool saveHistory = pSettings->value(IDS_HISTORY, IDS_HISTORY_VAL).toBool();
		if(saveHistory) {
			QString szMessageLog = pInlineMessageLog->prepareMessageLogForSave();
			History::save(inlinePeerName, QDateTime::currentDateTime(), &szMessageLog);
		}
	}

	pSettings->beginWriteArray(IDS_GROUPEXPHDR);
	for(int index = 0; index < ui.tvUserList->topLevelItemCount(); index++) {
		pSettings->setArrayIndex(index);
		pSettings->setValue(IDS_GROUP, ui.tvUserList->topLevelItem(index)->isExpanded());
	}
	pSettings->endArray();

	pTrayIcon->hide();

	//	process all temp message cache files - save to history but keep them for next session
	QDir cacheDir(StdLocation::cacheDir());
	if(!cacheDir.exists())
		return;
	QDir::Filters filters = QDir::Files | QDir::Readable;
	QDir::SortFlags sort = QDir::Name;
	QString filter = "msg_*.tmp";
	QStringList fileNames = cacheDir.entryList(QStringList() << filter, filters, sort);
	bool saveHistory = pSettings->value(IDS_HISTORY, IDS_HISTORY_VAL).toBool();
	if(saveHistory) {
		lmcMessageLog* pMessageLog = new lmcMessageLog();
		foreach(QString fileName, fileNames) {
			QString filePath = cacheDir.absoluteFilePath(fileName);
			pMessageLog->restoreMessageLog(filePath, false);
			if(pMessageLog->hasData) {
				QString szMessageLog = pMessageLog->prepareMessageLogForSave();
				History::save(pMessageLog->peerName, QDateTime::currentDateTime(), &szMessageLog);
			}
		}
		pMessageLog->deleteLater();
	}

	//	delete all other temp files (not msg_*.tmp)
	filter = "*.tmp";
	fileNames = cacheDir.entryList(QStringList() << filter, filters, sort);
	foreach(QString fileName, fileNames) {
		if(!fileName.startsWith("msg_"))
			QFile::remove(cacheDir.absoluteFilePath(fileName));
	}
}

void lmcMainWindow::addUser(User* pUser) {
	if(!pUser)
		return;

	int index = Helper::statusIndexFromCode(pUser->status);

	lmcUserTreeWidgetUserItem *pItem = new lmcUserTreeWidgetUserItem();
	pItem->setData(0, IdRole, pUser->id);
	pItem->setData(0, TypeRole, "User");
	pItem->setData(0, StatusRole, index);
	pItem->setData(0, SubtextRole, pUser->note);
    pItem->setData(0, CapsRole, pUser->caps);
	pItem->setText(0, pUser->name);
	if(statusToolTip)
		pItem->setToolTip(0, lmcStrings::statusDesc()[index]);
	
	if(index != -1)
		pItem->setIcon(0, QIcon(QPixmap(statusPic[index], "PNG")));

	lmcUserTreeWidgetGroupItem* pGroupItem = (lmcUserTreeWidgetGroupItem*)getGroupItem(&pUser->group);
	pGroupItem->addChild(pItem);
	pGroupItem->sortChildren(0, Qt::AscendingOrder);

	// this should be called after item has been added to tree
    setUserAvatar(&pUser->id, &pUser->avatarPath);

	if(isHidden() || !isActiveWindow()) {
		QString msg = tr("%1 is online.");
		showTrayMessage(TM_Status, msg.arg(pItem->text(0)));
		pSoundPlayer->play(SE_UserOnline);
	}

	sendAvatar(&pUser->id);
}

void lmcMainWindow::updateUser(User* pUser) {
	if(!pUser)
		return;

	QTreeWidgetItem* pItem = getUserItem(&pUser->id);
	if(pItem) {
		updateStatusImage(pItem, &pUser->status);
		int index = Helper::statusIndexFromCode(pUser->status);
		pItem->setData(0, StatusRole, index);
		pItem->setData(0, SubtextRole, pUser->note);
		pItem->setText(0, pUser->name);
		if(statusToolTip)
			pItem->setToolTip(0, lmcStrings::statusDesc()[index]);
		QTreeWidgetItem* pGroupItem = pItem->parent();
		pGroupItem->sortChildren(0, Qt::AscendingOrder);

		// Update inline chat header if this is the current chat
		if(currentChatPeer == pUser->id) {
			ui.lblChatStatus->setText(lmcStrings::statusDesc()[index]);
		}
	}
}

void lmcMainWindow::removeUser(QString* lpszUserId) {
	QTreeWidgetItem* pItem = getUserItem(lpszUserId);
	if(!pItem)
		return;
		
	QTreeWidgetItem* pGroup = pItem->parent();
	pGroup->removeChild(pItem);

	if(isHidden() || !isActiveWindow()) {
		QString msg = tr("%1 is offline.");
		showTrayMessage(TM_Status, msg.arg(pItem->text(0)));
		pSoundPlayer->play(SE_UserOffline);
	}
}

void lmcMainWindow::receiveMessage(MessageType type, QString* lpszUserId, XmlMessage* pMessage) {
	QString filePath;

	switch(type) {
	case MT_Avatar:
        filePath = pMessage->data(XN_FILEPATH);
        setUserAvatar(lpszUserId, &filePath);
		break;
	default:
		break;
	}
}

void lmcMainWindow::connectionStateChanged(bool connected) {
	if(connected)
		showTrayMessage(TM_Connection, tr("You are online."));
	else
		showTrayMessage(TM_Connection, tr("You are no longer connected."), lmcStrings::appName(), TMI_Warning);

	bConnected = connected;
	setTrayTooltip();
}

void lmcMainWindow::settingsChanged(bool init) {
	showSysTray = pSettings->value(IDS_SYSTRAY, IDS_SYSTRAY_VAL).toBool();
	showSysTrayMsg = pSettings->value(IDS_SYSTRAYMSG, IDS_SYSTRAYMSG_VAL).toBool();
	//	this setting should be loaded only at window init
	if(init)
		showMinimizeMsg = pSettings->value(IDS_MINIMIZEMSG, IDS_MINIMIZEMSG_VAL).toBool();
	//	this operation should not be done when window inits
	if(!init)
		pTrayIcon->setVisible(showSysTray);
	minimizeHide = pSettings->value(IDS_MINIMIZETRAY, IDS_MINIMIZETRAY_VAL).toBool();
	singleClickActivation = pSettings->value(IDS_SINGLECLICKTRAY, IDS_SINGLECLICKTRAY_VAL).toBool();
	allowSysTrayMinimize = pSettings->value(IDS_ALLOWSYSTRAYMIN, IDS_ALLOWSYSTRAYMIN_VAL).toBool();
	showAlert = pSettings->value(IDS_ALERT, IDS_ALERT_VAL).toBool();
	noBusyAlert = pSettings->value(IDS_NOBUSYALERT, IDS_NOBUSYALERT_VAL).toBool();
	noDNDAlert = pSettings->value(IDS_NODNDALERT, IDS_NODNDALERT_VAL).toBool();
	statusToolTip = pSettings->value(IDS_STATUSTOOLTIP, IDS_STATUSTOOLTIP_VAL).toBool();
	int viewType = pSettings->value(IDS_USERLISTVIEW, IDS_USERLISTVIEW_VAL).toInt();
	ui.tvUserList->setView((UserListView)viewType);
	for(int index = 0; index < ui.tvUserList->topLevelItemCount(); index++) {
		QTreeWidgetItem* item = ui.tvUserList->topLevelItem(index);
		for(int childIndex = 0; childIndex < item->childCount(); childIndex++) {
			QTreeWidgetItem* childItem = item->child(childIndex);

			QString toolTip = statusToolTip ? lmcStrings::statusDesc()[childItem->data(0, StatusRole).toInt()] : QString();
			childItem->setToolTip(0, toolTip);
		}
	}
	pSoundPlayer->settingsChanged();
	ui.lblUserName->setText(pLocalUser->name);	// in case display name has been changed

	// Inline chat settings
	inlineShowSmiley = pSettings->value(IDS_EMOTICON, IDS_EMOTICON_VAL).toBool();
	pInlineMessageLog->showSmiley = inlineShowSmiley;
	pInlineMessageLog->fontSizeVal = pSettings->value(IDS_FONTSIZE, IDS_FONTSIZE_VAL).toInt();
	pInlineMessageLog->messageTime = pSettings->value(IDS_MESSAGETIME, IDS_MESSAGETIME_VAL).toBool();
	pInlineMessageLog->messageDate = pSettings->value(IDS_MESSAGEDATE, IDS_MESSAGEDATE_VAL).toBool();
	pInlineMessageLog->allowLinks = pSettings->value(IDS_ALLOWLINKS, IDS_ALLOWLINKS_VAL).toBool();
	pInlineMessageLog->pathToLink = pSettings->value(IDS_PATHTOLINK, IDS_PATHTOLINK_VAL).toBool();
	pInlineMessageLog->trimMessage = pSettings->value(IDS_TRIMMESSAGE, IDS_TRIMMESSAGE_VAL).toBool();
	QFont font = QApplication::font();
	font.fromString(pSettings->value(IDS_FONT, IDS_FONT_VAL).toString());
	pInlineMessageLog->setFont(font);
	inlineMessageColor = QColor("#ffffff");
	ui.txtChatMessage->setStyleSheet("QTextEdit {color: #ffffff;}");
	QString themePath = pSettings->value(IDS_THEME, IDS_THEME_VAL).toString();
	pInlineMessageLog->initMessageLog(themePath);
}

void lmcMainWindow::showTrayMessage(TrayMessageType type, QString szMessage, QString szTitle, TrayMessageIcon icon) {
	if(!showSysTray || !showSysTrayMsg)
		return;

	bool showMsg = showSysTray;
	
	switch(type) {
	case TM_Status:
		if(!showAlert || (pLocalUser->status == "Busy" && noBusyAlert) || (pLocalUser->status == "NoDisturb" && noDNDAlert))
			return;
		break;
    default:
        break;
	}

	if(szTitle.isNull())
		szTitle = lmcStrings::appName();

	QSystemTrayIcon::MessageIcon trayIcon = QSystemTrayIcon::Information;
	switch(icon) {
	case TMI_Info:
		trayIcon = QSystemTrayIcon::Information;
		break;
	case TMI_Warning:
		trayIcon = QSystemTrayIcon::Warning;
		break;
	case TMI_Error:
		trayIcon = QSystemTrayIcon::Critical;
		break;
    default:
        break;
	}

	if(showMsg) {
		lastTrayMessageType = type;
		pTrayIcon->showMessage(szTitle, szMessage, trayIcon);
	}
}

QList<QTreeWidgetItem*> lmcMainWindow::getContactsList(void) {
	QList<QTreeWidgetItem*> contactsList;
	for(int index = 0; index < ui.tvUserList->topLevelItemCount(); index++)
		contactsList.append(ui.tvUserList->topLevelItem(index)->clone());

	return contactsList;
}

bool lmcMainWindow::eventFilter(QObject* pObject, QEvent* pEvent) {
    if(pEvent->type() == QEvent::KeyPress) {
        QKeyEvent* pKeyEvent = static_cast<QKeyEvent*>(pEvent);
        if(pKeyEvent->key() == Qt::Key_Escape) {
            close();
            return true;
        }
		// Handle send shortcut in chat input
		if(pObject == ui.txtChatMessage) {
			bool ctrlEnter = pSettings->value(IDS_SENDKEYMOD, IDS_SENDKEYMOD_VAL).toBool();
			if(ctrlEnter) {
				if(pKeyEvent->key() == Qt::Key_Return && pKeyEvent->modifiers() == Qt::ControlModifier) {
					inlineSendMessage();
					return true;
				}
			} else {
				if(pKeyEvent->key() == Qt::Key_Return && pKeyEvent->modifiers() == Qt::NoModifier) {
					inlineSendMessage();
					return true;
				}
				if(pKeyEvent->key() == Qt::Key_Return && pKeyEvent->modifiers() == Qt::ShiftModifier) {
					// Allow newline
					return false;
				}
			}
		}
    }

    return false;
}

void lmcMainWindow::closeEvent(QCloseEvent* pEvent) {
	//	close main window to system tray
	pEvent->ignore();
	minimize();
}

void lmcMainWindow::changeEvent(QEvent* pEvent) {
	switch(pEvent->type()) {
	case QEvent::WindowStateChange:
		// Maximize button icon stays the same (restore behavior handled by slot)
		if(minimizeHide) {
			QWindowStateChangeEvent* e = (QWindowStateChangeEvent*)pEvent;
			if(isMinimized() && e->oldState() != Qt::WindowMinimized) {
				QTimer::singleShot(0, this, SLOT(hide()));
				pEvent->ignore();
				showMinimizeMessage();
			}
		}
		break;
	case QEvent::LanguageChange:
		setUIText();
		break;
    default:
        break;
	}

	QWidget::changeEvent(pEvent);
}

void lmcMainWindow::sendMessage(MessageType type, QString* lpszUserId, XmlMessage* pMessage) {
	emit messageSent(type, lpszUserId, pMessage);
}

void lmcMainWindow::trayShowAction_triggered(void) {
	restore();
}

void lmcMainWindow::trayHistoryAction_triggered(void) {
	emit showHistory();
}

void lmcMainWindow::trayFileAction_triggered(void) {
	emit showTransfers();
}

void lmcMainWindow::traySettingsAction_triggered(void) {
	emit showSettings();
}

void lmcMainWindow::trayAboutAction_triggered(void) {
	emit showAbout();
}

void lmcMainWindow::trayExitAction_triggered(void) {
	emit appExiting();
}

void lmcMainWindow::statusAction_triggered(QAction* action) {
	QString status = action->data().toString();
	int index = Helper::statusIndexFromCode(status);
	if(index != -1) {
		btnStatus->setIcon(QIcon(QPixmap(statusPic[index], "PNG")));
		ui.lblStatus->setText(statusGroup->checkedAction()->text());
		pLocalUser->status = statusCode[index];
		pSettings->setValue(IDS_STATUS, pLocalUser->status);

		sendMessage(MT_Status, NULL, &status);
	}
}

void lmcMainWindow::avatarAction_triggered(void) {
	setAvatar();
}

void lmcMainWindow::avatarBrowseAction_triggered(void) {
	QString dir = pSettings->value(IDS_OPENPATH, IDS_OPENPATH_VAL).toString();
	QString fileName = QFileDialog::getOpenFileName(this, tr("Select avatar picture"), dir,
		"Images (*.bmp *.gif *.jpg *.jpeg *.png *.tif *.tiff)");
	if(!fileName.isEmpty()) {
		pSettings->setValue(IDS_OPENPATH, QFileInfo(fileName).dir().absolutePath());
		setAvatar(fileName);
	}
}

void lmcMainWindow::chatRoomAction_triggered(void) {
	// Generate a thread id which is a combination of the local user id and a guid
	// This ensures that no other user will generate an identical thread id
	QString threadId = Helper::getUuid();
	threadId.prepend(pLocalUser->id);
	emit chatRoomStarting(&threadId);
}

void lmcMainWindow::publicChatAction_triggered(void) {
	emit showPublicChat();
}

void lmcMainWindow::searchBar_textChanged(const QString& text) {
	for(int top = 0; top < ui.tvUserList->topLevelItemCount(); top++) {
		QTreeWidgetItem* group = ui.tvUserList->topLevelItem(top);
		int visibleCount = 0;
		for(int i = 0; i < group->childCount(); i++) {
			QTreeWidgetItem* user = group->child(i);
			bool match = text.isEmpty() || user->text(0).contains(text, Qt::CaseInsensitive);
			user->setHidden(!match);
			if(match) visibleCount++;
		}
		group->setHidden(visibleCount == 0);
	}
}

void lmcMainWindow::refreshAction_triggered(void) {
    QString szUserId;
    QString szMessage;

	sendMessage(MT_Refresh, &szUserId, &szMessage);
}

void lmcMainWindow::helpAction_triggered(void) {
	QRect rect = geometry();
	emit showHelp(&rect);
}

void lmcMainWindow::homePageAction_triggered(void) {
	QDesktopServices::openUrl(QUrl(IDA_DOMAIN));
}

void lmcMainWindow::updateAction_triggered(void) {
	QRect rect = geometry();
	emit showUpdate(&rect);
}

void lmcMainWindow::trayIcon_activated(QSystemTrayIcon::ActivationReason reason) {
	switch(reason) {
	case QSystemTrayIcon::Trigger:
		if(singleClickActivation)
			processTrayIconTrigger();
		break;
	case QSystemTrayIcon::DoubleClick:
		if(!singleClickActivation)
			processTrayIconTrigger();
		break;
    default:
        break;
	}
}

void lmcMainWindow::trayMessage_clicked(void) {
	switch(lastTrayMessageType) {
	case TM_Status:
		trayShowAction_triggered();
		break;
	case TM_Transfer:
		emit showTransfers();
		break;
    default:
        break;
	}
}

void lmcMainWindow::tvUserList_itemActivated(QTreeWidgetItem* pItem, int column) {
    Q_UNUSED(column);
    if(pItem->data(0, TypeRole).toString().compare("User") == 0) {
        QString szUserId = pItem->data(0, IdRole).toString();
        showInlineChat(&szUserId);
    }
}

void lmcMainWindow::tvUserList_itemContextMenu(QTreeWidgetItem* pItem, QPoint& pos) {
    if(!pItem)
        return;

    if(pItem->data(0, TypeRole).toString().compare("Group") == 0) {
        for(int index = 0; index < pGroupMenu->actions().count(); index++)
            pGroupMenu->actions()[index]->setData(pItem->data(0, IdRole));

		bool defGroup = (pItem->data(0, IdRole).toString().compare(GRP_DEFAULT_ID) == 0);
        pGroupMenu->actions()[3]->setEnabled(!defGroup);
        pGroupMenu->exec(pos);
    } else if(pItem->data(0, TypeRole).toString().compare("User") == 0) {
        for(int index = 0; index < pUserMenu->actions().count(); index++)
            pUserMenu->actions()[index]->setData(pItem->data(0, IdRole));

        bool fileCap = ((pItem->data(0, CapsRole).toUInt() & UC_File) == UC_File);
        pUserMenu->actions()[1]->setEnabled(fileCap);
        bool folderCap = ((pItem->data(0, CapsRole).toUInt() & UC_Folder) == UC_Folder);
        pUserMenu->actions()[2]->setEnabled(folderCap);
        pUserMenu->exec(pos);
    }
}

void lmcMainWindow::tvUserList_itemDragDropped(QTreeWidgetItem* pItem) {
    if(dynamic_cast<lmcUserTreeWidgetUserItem*>(pItem)) {
        QString szUserId = pItem->data(0, IdRole).toString();
        QString szMessage = pItem->parent()->data(0, IdRole).toString();
        sendMessage(MT_Group, &szUserId, &szMessage);
		QTreeWidgetItem* pGroupItem = pItem->parent();
		pGroupItem->sortChildren(0, Qt::AscendingOrder);
    }
	else if(dynamic_cast<lmcUserTreeWidgetGroupItem*>(pItem)) {
		int index = ui.tvUserList->indexOfTopLevelItem(pItem);
		QString groupId = pItem->data(0, IdRole).toString();
		emit groupUpdated(GO_Move, groupId, index);
	}
}

void lmcMainWindow::tvUserList_currentItemChanged(QTreeWidgetItem *pCurrent, QTreeWidgetItem *pPrevious) {
	Q_UNUSED(pPrevious);
	bool bEnabled = (pCurrent && pCurrent->data(0, TypeRole).toString().compare("User") == 0);
	toolChatButton->setEnabled(bEnabled);
	toolFileButton->setEnabled(bEnabled);
}

void lmcMainWindow::groupAddAction_triggered(void) {
	QString groupName = QInputDialog::getText(this, tr("Add New Group"), tr("Enter a name for the group"));

	if(groupName.isNull())
		return;

	if(getGroupItemByName(&groupName)) {
		QString msg = tr("A group named '%1' already exists. Please enter a different name.");
		QMessageBox::warning(this, lmcStrings::appName(), msg.arg(groupName));
		return;
	}

	//generate a group id that is not assigned to any existing group
	QString groupId;
	do {
		groupId = Helper::getUuid();
	} while(getGroupItem(&groupId));
	
	emit groupUpdated(GO_New, groupId, groupName);
	lmcUserTreeWidgetGroupItem *pItem = new lmcUserTreeWidgetGroupItem();
	pItem->setData(0, IdRole, groupId);
	pItem->setData(0, TypeRole, "Group");
	pItem->setText(0, groupName);
	pItem->setSizeHint(0, QSize(0, 20));
	ui.tvUserList->addTopLevelItem(pItem);
	//	set the item as expanded after adding it to the treeview, else wont work
	pItem->setExpanded(true);
}

void lmcMainWindow::groupRenameAction_triggered(void) {
	QTreeWidgetItem* pGroupItem = ui.tvUserList->currentItem();
	QString groupId = pGroupItem->data(0, IdRole).toString();
	QString oldName = pGroupItem->data(0, Qt::DisplayRole).toString();
	QString newName = QInputDialog::getText(this, tr("Rename Group"), 
		tr("Enter a new name for the group"), QLineEdit::Normal, oldName);

	if(newName.isNull() || newName.compare(oldName) == 0)
		return;

	if(getGroupItemByName(&newName)) {
		QString msg = tr("A group named '%1' already exists. Please enter a different name.");
		QMessageBox::warning(this, lmcStrings::appName(), msg.arg(newName));
		return;
	}

	emit groupUpdated(GO_Rename, groupId, newName);
	pGroupItem->setText(0, newName);
}

void lmcMainWindow::groupDeleteAction_triggered(void) {
	QTreeWidgetItem* pGroupItem = ui.tvUserList->currentItem();
	QString groupId = pGroupItem->data(0, IdRole).toString();
	QString defGroupId = GRP_DEFAULT_ID;
	QTreeWidgetItem* pDefGroupItem = getGroupItem(&defGroupId);
	while(pGroupItem->childCount()) {
		QTreeWidgetItem* pUserItem = pGroupItem->child(0);
		pGroupItem->removeChild(pUserItem);
		pDefGroupItem->addChild(pUserItem);
        QString szUserId = pUserItem->data(0, IdRole).toString();
        QString szMessage = pUserItem->parent()->data(0, IdRole).toString();
        sendMessage(MT_Group, &szUserId, &szMessage);
	}
	pDefGroupItem->sortChildren(0, Qt::AscendingOrder);

	emit groupUpdated(GO_Delete, groupId, QVariant());
	ui.tvUserList->takeTopLevelItem(ui.tvUserList->indexOfTopLevelItem(pGroupItem));
}

void lmcMainWindow::userConversationAction_triggered(void) {
	QString userId = ui.tvUserList->currentItem()->data(0, IdRole).toString();
	showInlineChat(&userId);
}

void lmcMainWindow::userBroadcastAction_triggered(void) {
	emit showBroadcast();
}

void lmcMainWindow::userFileAction_triggered(void) {
	QString userId = ui.tvUserList->currentItem()->data(0, IdRole).toString();
	QString dir = pSettings->value(IDS_OPENPATH, IDS_OPENPATH_VAL).toString();
	QString fileName = QFileDialog::getOpenFileName(this, QString(), dir);
	if(!fileName.isEmpty()) {
		pSettings->setValue(IDS_OPENPATH, QFileInfo(fileName).dir().absolutePath());
        sendMessage(MT_File, &userId, &fileName);
	}
}

void lmcMainWindow::userFolderAction_triggered(void) {
    QString userId = ui.tvUserList->currentItem()->data(0, IdRole).toString();
    QString dir = pSettings->value(IDS_OPENPATH, IDS_OPENPATH_VAL).toString();
    QString path = QFileDialog::getExistingDirectory(this, QString(), dir, QFileDialog::ShowDirsOnly);
    if(!path.isEmpty()) {
        pSettings->setValue(IDS_OPENPATH, QFileInfo(path).absolutePath());
        sendMessage(MT_Folder, &userId, &path);
    }
}

void lmcMainWindow::userInfoAction_triggered(void) {
	QString userId = ui.tvUserList->currentItem()->data(0, IdRole).toString();
	QString message;
	sendMessage(MT_Query, &userId, &message);
}

void lmcMainWindow::txtNote_returnPressed(void) {
	//	Shift the focus from txtNote to another control
	ui.tvUserList->setFocus();
}

void lmcMainWindow::txtNote_lostFocus(void) {
	QString note = ui.txtNote->text();
    pSettings->setValue(IDS_NOTE, note, IDS_NOTE_VAL);
	pLocalUser->note = note;
	sendMessage(MT_Note, NULL, &note);
}

void lmcMainWindow::createMainMenu(void) {
	pMainMenu = new QMenu(this);
	pFileMenu = pMainMenu->addMenu("&Messenger");
	chatRoomAction = pFileMenu->addAction("&New Chat Room", QKeySequence::New, this,
		SLOT(chatRoomAction_triggered()));
	publicChatAction = pFileMenu->addAction(QIcon(QPixmap(IDR_CHATROOM, "PNG")), "&Public Chat",
		this, SLOT(publicChatAction_triggered()));
	pFileMenu->addSeparator();
	refreshAction = pFileMenu->addAction(QIcon(QPixmap(IDR_REFRESH, "PNG")), "&Refresh contacts list",
		QKeySequence::Refresh, this, SLOT(refreshAction_triggered()));
	pFileMenu->addSeparator();
	exitAction = pFileMenu->addAction(QIcon(QPixmap(IDR_CLOSE, "PNG")), "E&xit", 
		this, SLOT(trayExitAction_triggered()));
	pToolsMenu = pMainMenu->addMenu("&Tools");
	historyAction = pToolsMenu->addAction(QIcon(QPixmap(IDR_HISTORY, "PNG")), "&History",
		QKeySequence(Qt::CTRL | Qt::Key_H), this, SLOT(trayHistoryAction_triggered()));
	transferAction = pToolsMenu->addAction(QIcon(QPixmap(IDR_TRANSFER, "PNG")), "File &Transfers",
		QKeySequence(Qt::CTRL | Qt::Key_J), this, SLOT(trayFileAction_triggered()));
	pToolsMenu->addSeparator();
	settingsAction = pToolsMenu->addAction(QIcon(QPixmap(IDR_TOOLS, "PNG")), "&Preferences",
		QKeySequence::Preferences, this, SLOT(traySettingsAction_triggered()));
	pHelpMenu = pMainMenu->addMenu("&Help");
	helpAction = pHelpMenu->addAction(QIcon(QPixmap(IDR_QUESTION, "PNG")), "&Help",
		QKeySequence::HelpContents, this, SLOT(helpAction_triggered()));
	pHelpMenu->addSeparator();
	QString text = "%1 &online";
	onlineAction = pHelpMenu->addAction(QIcon(QPixmap(IDR_WEB, "PNG")), text.arg(lmcStrings::appName()), 
		this, SLOT(homePageAction_triggered()));
	updateAction = pHelpMenu->addAction("Check for &Updates", this, SLOT(updateAction_triggered()));
	aboutAction = pHelpMenu->addAction(QIcon(QPixmap(IDR_INFO, "PNG")), "&About", this, SLOT(trayAboutAction_triggered()));

	ui.wgtMenuBar->hide();
}

void lmcMainWindow::createTrayMenu(void) {
	pTrayMenu = new QMenu(this);
	
	QString text = "&Show %1";
	trayShowAction = pTrayMenu->addAction(QIcon(QPixmap(IDR_MESSENGER, "PNG")), text.arg(lmcStrings::appName()), 
		this, SLOT(trayShowAction_triggered()));
	pTrayMenu->addSeparator();
	trayStatusAction = pTrayMenu->addMenu(pStatusMenu);
	trayStatusAction->setText("&Change Status");
	pTrayMenu->addSeparator();
	trayHistoryAction = pTrayMenu->addAction(QIcon(QPixmap(IDR_HISTORY, "PNG")), "&History",
		this, SLOT(trayHistoryAction_triggered()));
	trayTransferAction = pTrayMenu->addAction(QIcon(QPixmap(IDR_TRANSFER, "PNG")), "File &Transfers",
		this, SLOT(trayFileAction_triggered()));
	pTrayMenu->addSeparator();
	traySettingsAction = pTrayMenu->addAction(QIcon(QPixmap(IDR_TOOLS, "PNG")), "&Preferences",
		this, SLOT(traySettingsAction_triggered()));
	trayAboutAction = pTrayMenu->addAction(QIcon(QPixmap(IDR_INFO, "PNG")), "&About",
		this, SLOT(trayAboutAction_triggered()));
	pTrayMenu->addSeparator();
	trayExitAction = pTrayMenu->addAction(QIcon(QPixmap(IDR_CLOSE, "PNG")), "E&xit", this, SLOT(trayExitAction_triggered()));

	pTrayMenu->setDefaultAction(trayShowAction);
}

void lmcMainWindow::createTrayIcon(void) {
	pTrayIcon = new QSystemTrayIcon(this);
	pTrayIcon->setIcon(QIcon(IDR_APPICON));
	pTrayIcon->setContextMenu(pTrayMenu);
	
	connect(pTrayIcon, SIGNAL(activated(QSystemTrayIcon::ActivationReason)), 
		this, SLOT(trayIcon_activated(QSystemTrayIcon::ActivationReason)));
	connect(pTrayIcon, SIGNAL(messageClicked()), this, SLOT(trayMessage_clicked()));
}

void lmcMainWindow::createStatusMenu(void) {
	pStatusMenu = new QMenu(this);
	pStatusMenu->setObjectName("statusMenu");
	statusGroup = new QActionGroup(this);
	connect(statusGroup, SIGNAL(triggered(QAction*)), this, SLOT(statusAction_triggered(QAction*)));

	for(int index = 0; index < ST_COUNT; index++) {
		QAction* pAction = new QAction(QIcon(QPixmap(statusPic[index], "PNG")), lmcStrings::statusDesc()[index], this);
		pAction->setData(statusCode[index]);
		pAction->setCheckable(true);
		statusGroup->addAction(pAction);
		pStatusMenu->addAction(pAction);
	}

	btnStatus->setMenu(pStatusMenu);
}

void lmcMainWindow::createAvatarMenu(void) {
	pAvatarMenu = new QMenu(this);

	lmcImagePickerAction* pAction = new lmcImagePickerAction(this, avtPic, AVT_COUNT, 48, 4, &nAvatar);
	connect(pAction, SIGNAL(triggered()), this, SLOT(avatarAction_triggered()));
	pAvatarMenu->addAction(pAction);
	pAvatarMenu->addSeparator();
	avatarBrowseAction = pAvatarMenu->addAction("&Select picture...", this, SLOT(avatarBrowseAction_triggered()));

	ui.btnAvatar->setMenu(pAvatarMenu);
}

void lmcMainWindow::createGroupMenu(void) {
	pGroupMenu = new QMenu(this);

	groupAddAction = pGroupMenu->addAction("Add &New Group", this, SLOT(groupAddAction_triggered()));
	pGroupMenu->addSeparator();
	groupRenameAction = pGroupMenu->addAction("&Rename This Group", this, SLOT(groupRenameAction_triggered()));
	groupDeleteAction = pGroupMenu->addAction("&Delete This Group", this, SLOT(groupDeleteAction_triggered()));
}

void lmcMainWindow::createUserMenu(void) {
	pUserMenu = new QMenu(this);

	userChatAction = pUserMenu->addAction("&Conversation", this, SLOT(userConversationAction_triggered()));
	userFileAction = pUserMenu->addAction("Send &File", this, SLOT(userFileAction_triggered()));
    userFolderAction = pUserMenu->addAction("Send a Fol&der", this, SLOT(userFolderAction_triggered()));
	pUserMenu->addSeparator();
	userBroadcastAction = pUserMenu->addAction("Send &Broadcast Message", this, SLOT(userBroadcastAction_triggered()));
	pUserMenu->addSeparator();
	userInfoAction = pUserMenu->addAction("Get &Information", this, SLOT(userInfoAction_triggered()));
}

void lmcMainWindow::createToolBar(void) {
	QToolBar* pStatusBar = new QToolBar(ui.frame);
	pStatusBar->setStyleSheet("QToolBar { border: 0px; padding: 0px; }");
	ui.statusLayout->insertWidget(0, pStatusBar);
	QAction* pStatusAction = pStatusBar->addAction("");
	btnStatus = (QToolButton*)pStatusBar->widgetForAction(pStatusAction);
	btnStatus->setObjectName("btnStatus");
	btnStatus->setFixedSize(32, 32);
	btnStatus->setIconSize(QSize(20, 20));
	btnStatus->setPopupMode(QToolButton::InstantPopup);

	auto addBtn = [&](QIcon icon, QString tip, const char* slot) -> QToolButton* {
		QToolButton* btn = new QToolButton(ui.wgtToolBar);
		btn->setIcon(icon);
		btn->setIconSize(QSize(40, 20));
		btn->setToolButtonStyle(Qt::ToolButtonIconOnly);
		btn->setAutoRaise(false);
		btn->setToolTip(tip);
		QObject::connect(btn, SIGNAL(clicked()), this, slot);
		ui.toolBarLayout->addWidget(btn);
		return btn;
	};
	auto addSpacer = [&](int w) {
		QWidget* sp = new QWidget(ui.wgtToolBar);
		sp->setFixedWidth(w);
		ui.toolBarLayout->addWidget(sp);
	};

	toolChatButton = addBtn(QIcon(QPixmap(IDR_CHAT, "PNG")), tr("&Conversation"), SLOT(userConversationAction_triggered()));
	toolChatButton->setEnabled(false);
	addSpacer(6);
	toolFileButton = addBtn(QIcon(QPixmap(IDR_FILE, "PNG")), tr("Send &File"), SLOT(userFileAction_triggered()));
	toolFileButton->setEnabled(false);
	addSpacer(6);
	toolBroadcastButton = addBtn(QIcon(QPixmap(IDR_BROADCASTMSG, "PNG")), tr("Send &Broadcast Message"), SLOT(userBroadcastAction_triggered()));
	addSpacer(6);
	toolChatRoomButton = addBtn(QIcon(QPixmap(IDR_NEWCHATROOM, "PNG")), tr("&New Chat Room"), SLOT(chatRoomAction_triggered()));
	addSpacer(6);
	toolPublicChatButton = addBtn(QIcon(QPixmap(IDR_CHATROOM, "PNG")), tr("&Public Chat"), SLOT(publicChatAction_triggered()));
	addSpacer(6);
	toolRefreshButton = addBtn(QIcon(QPixmap(IDR_REFRESH, "PNG")), tr("&Refresh Contacts"), SLOT(refreshAction_triggered()));

	searchBar = new QLineEdit(ui.leftPanel);
	searchBar->setPlaceholderText(tr("Search contacts..."));
	searchBar->setClearButtonEnabled(true);
	searchBar->setFixedHeight(36);
	searchBar->setStyleSheet(
		"QLineEdit { background: #202225; border: 1px solid #040405; border-radius: 2px; "
		"padding: 4px 6px; color: #dcddde; }"
		"QLineEdit:focus { border-color: #7289da; }"
	);
	connect(searchBar, SIGNAL(textChanged(const QString&)), this, SLOT(searchBar_textChanged(const QString&)));
	QWidget* searchSpacer = new QWidget(ui.leftPanel);
	searchSpacer->setFixedHeight(5);
	ui.leftPanelLayout->addWidget(searchSpacer);
	ui.leftPanelLayout->addWidget(searchBar);
}

void lmcMainWindow::setUIText(void) {
	ui.retranslateUi(this);

	setWindowTitle(lmcStrings::appName());

	pFileMenu->setTitle(tr("&Messenger"));
	chatRoomAction->setText(tr("&New Chat Room"));
	publicChatAction->setText(tr("&Public Chat"));
	refreshAction->setText(tr("&Refresh Contacts List"));
	exitAction->setText(tr("E&xit"));
	pToolsMenu->setTitle(tr("&Tools"));
	historyAction->setText(tr("&History"));
	transferAction->setText(tr("File &Transfers"));
	settingsAction->setText(tr("&Preferences"));
	pHelpMenu->setTitle(tr("&Help"));
	helpAction->setText(tr("&Help"));
	QString text = tr("%1 &online");
	onlineAction->setText(text.arg(lmcStrings::appName()));
	updateAction->setText(tr("Check for &Updates..."));
	aboutAction->setText(tr("&About"));
	text = tr("&Show %1");
	trayShowAction->setText(text.arg(lmcStrings::appName()));
	trayStatusAction->setText(tr("&Change Status"));
	trayHistoryAction->setText(tr("&History"));
	trayTransferAction->setText(tr("File &Transfers"));
	traySettingsAction->setText(tr("&Preferences"));
	trayAboutAction->setText(tr("&About"));
	trayExitAction->setText(tr("E&xit"));
	groupAddAction->setText(tr("Add &New Group"));
	groupRenameAction->setText(tr("&Rename This Group"));
	groupDeleteAction->setText(tr("&Delete This Group"));
	userChatAction->setText(tr("&Conversation"));
	userBroadcastAction->setText(tr("Send &Broadcast Message"));
	userFileAction->setText(tr("Send &File"));
    userFolderAction->setText(tr("Send Fol&der"));
	userInfoAction->setText(tr("Get &Information"));
	avatarBrowseAction->setText(tr("&Browse for more pictures..."));
	toolChatButton->setToolTip(tr("&Conversation"));
	toolFileButton->setToolTip(tr("Send &File"));
	toolBroadcastButton->setToolTip(tr("Send &Broadcast Message"));
	toolChatRoomButton->setToolTip(tr("&New Chat Room"));
	toolPublicChatButton->setToolTip(tr("&Public Chat"));
	toolRefreshButton->setToolTip(tr("&Refresh Contacts"));
	searchBar->setPlaceholderText(tr("Search contacts..."));

	for(int index = 0; index < statusGroup->actions().count(); index++)
		statusGroup->actions()[index]->setText(lmcStrings::statusDesc()[index]);
	
	ui.lblUserName->setText(pLocalUser->name);	// in case of retranslation
	if(statusGroup->checkedAction())
		ui.lblStatus->setText(statusGroup->checkedAction()->text());

	for(int index = 0; index < ui.tvUserList->topLevelItemCount(); index++) {
		QTreeWidgetItem* item = ui.tvUserList->topLevelItem(index);
		for(int childIndex = 0; childIndex < item->childCount(); childIndex++) {
			QTreeWidgetItem*childItem = item->child(childIndex);
			int statusIndex = childItem->data(0, StatusRole).toInt();
			childItem->setToolTip(0, lmcStrings::statusDesc()[statusIndex]);
		}
	}

	setTrayTooltip();
}

void lmcMainWindow::showMinimizeMessage(void) {
	if(showMinimizeMsg) {
		QString msg = tr("%1 will continue to run in the background. Activate this icon to restore the application window.");
		showTrayMessage(TM_Minimize, msg.arg(lmcStrings::appName()));
		showMinimizeMsg = false;
	}
}

void lmcMainWindow::initGroups(QList<Group>* pGroupList) {
	for(int index = 0; index < pGroupList->count(); index++) {
		lmcUserTreeWidgetGroupItem *pItem = new lmcUserTreeWidgetGroupItem();
		pItem->setData(0, IdRole, pGroupList->value(index).id);
		pItem->setData(0, TypeRole, "Group");
		pItem->setText(0, pGroupList->value(index).name);
		pItem->setSizeHint(0, QSize(0, 30));
		ui.tvUserList->addTopLevelItem(pItem);
	}

	ui.tvUserList->expandAll();
	// size will be either number of items in group expansion list or number of top level items in
	// treeview control, whichever is less. This is to  eliminate arary out of bounds error.
	int size = qMin(pSettings->beginReadArray(IDS_GROUPEXPHDR), ui.tvUserList->topLevelItemCount());
	for(int index = 0; index < size; index++) {
		pSettings->setArrayIndex(index);
		ui.tvUserList->topLevelItem(index)->setExpanded(pSettings->value(IDS_GROUP).toBool());
	}
	pSettings->endArray();
}

void lmcMainWindow::updateStatusImage(QTreeWidgetItem* pItem, QString* lpszStatus) {
	int index = Helper::statusIndexFromCode(*lpszStatus);
	if(index != -1)
		pItem->setIcon(0, QIcon(QPixmap(statusPic[index], "PNG")));
}

void lmcMainWindow::setAvatar(QString fileName) {
	//	create cache folder if it does not exist
	QDir cacheDir(StdLocation::cacheDir());
	if(!cacheDir.exists())
		cacheDir.mkdir(cacheDir.absolutePath());
	QString filePath = StdLocation::avatarFile();

	//	Save the image as a file in the data folder
	QPixmap avatar;
    bool loadFromStdPath = false;
	if(!fileName.isEmpty()) {
		//	save a backup of the image in the cache folder
		avatar = QPixmap(fileName);
		nAvatar = -1;
	} else {
		//	nAvatar = -1 means custom avatar is set, otherwise load from resource
		if(nAvatar < 0) {
			//	load avatar from image file if file exists, else load default
            if(QFile::exists(filePath)) {
				avatar = QPixmap(filePath);
                loadFromStdPath = true;
            }
			else
				avatar = QPixmap(AVT_DEFAULT);
		} else
			avatar = QPixmap(avtPic[nAvatar]);
	}

    if(!loadFromStdPath) {
        avatar = avatar.scaled(QSize(AVT_WIDTH, AVT_HEIGHT), Qt::IgnoreAspectRatio, Qt::SmoothTransformation);
        avatar.save(filePath);
    }

	//	Apply 2px rounded corners to the avatar for btnAvatar
	QPixmap roundedAvatar(32, 32);
	roundedAvatar.fill(Qt::transparent);
	QPainter painter(&roundedAvatar);
	painter.setRenderHint(QPainter::Antialiasing);
	QPainterPath path;
	path.addRoundedRect(0, 0, 32, 32, 2, 2);
	painter.setClipPath(path);
	painter.drawPixmap(0, 0, 32, 32, QPixmap(filePath, "PNG"));
	painter.end();
	ui.btnAvatar->setIcon(QIcon(roundedAvatar));
	pLocalUser->avatar = nAvatar;
	sendAvatar(NULL);
}

QTreeWidgetItem* lmcMainWindow::getUserItem(QString* lpszUserId) {
	for(int topIndex = 0; topIndex < ui.tvUserList->topLevelItemCount(); topIndex++) {
		for(int index = 0; index < ui.tvUserList->topLevelItem(topIndex)->childCount(); index++) {
			QTreeWidgetItem* pItem = ui.tvUserList->topLevelItem(topIndex)->child(index);
			if(pItem->data(0, IdRole).toString().compare(*lpszUserId) == 0)
				return pItem;
		}
	}

	return NULL;
}

QTreeWidgetItem* lmcMainWindow::getGroupItem(QString* lpszGroupId) {
	for(int topIndex = 0; topIndex < ui.tvUserList->topLevelItemCount(); topIndex++) {
		QTreeWidgetItem* pItem = ui.tvUserList->topLevelItem(topIndex);
		if(pItem->data(0, IdRole).toString().compare(*lpszGroupId) == 0)
			return pItem;
	}

	return NULL;
}

QTreeWidgetItem* lmcMainWindow::getGroupItemByName(QString* lpszGroupName) {
	for(int topIndex = 0; topIndex < ui.tvUserList->topLevelItemCount(); topIndex++) {
		QTreeWidgetItem* pItem = ui.tvUserList->topLevelItem(topIndex);
		if(pItem->data(0, Qt::DisplayRole).toString().compare(*lpszGroupName) == 0)
			return pItem;
	}

	return NULL;
}

void lmcMainWindow::sendMessage(MessageType type, QString* lpszUserId, QString* lpszMessage) {
	XmlMessage xmlMessage;
	
	switch(type) {
	case MT_Status:
		xmlMessage.addData(XN_STATUS, *lpszMessage);
		break;
	case MT_Note:
		xmlMessage.addData(XN_NOTE, *lpszMessage);
		break;
	case MT_Refresh:
		break;
	case MT_Group:
		xmlMessage.addData(XN_GROUP, *lpszMessage);
		break;
    case MT_File:
    case MT_Folder:
		xmlMessage.addData(XN_FILETYPE, FileTypeNames[FT_Normal]);
		xmlMessage.addData(XN_FILEOP, FileOpNames[FO_Request]);
		xmlMessage.addData(XN_FILEPATH, *lpszMessage);
		break;
    case MT_Avatar:
        xmlMessage.addData(XN_FILETYPE, FileTypeNames[FT_Avatar]);
        xmlMessage.addData(XN_FILEOP, FileOpNames[FO_Request]);
        xmlMessage.addData(XN_FILEPATH, *lpszMessage);
        break;
	case MT_Query:
		xmlMessage.addData(XN_QUERYOP, QueryOpNames[QO_Get]);
		break;
	default:
		break;
	}

	sendMessage(type, lpszUserId, &xmlMessage);
}

void lmcMainWindow::sendAvatar(QString* lpszUserId) {
    QString filePath = StdLocation::avatarFile();
	if(!QFile::exists(filePath))
		return;

    sendMessage(MT_Avatar, lpszUserId, &filePath);
}

void lmcMainWindow::setUserAvatar(QString* lpszUserId, QString *lpszFilePath) {
	QTreeWidgetItem* pUserItem = getUserItem(lpszUserId);
	if(!pUserItem)
		return;

    QPixmap avatar;
    if(!lpszFilePath || !QFile::exists(*lpszFilePath))
        avatar.load(AVT_DEFAULT);
    else
        avatar.load(*lpszFilePath);
    avatar = avatar.scaled(QSize(32, 32), Qt::IgnoreAspectRatio, Qt::SmoothTransformation);
	pUserItem->setData(0, AvatarRole, QIcon(avatar));
}

void lmcMainWindow::processTrayIconTrigger(void) {
	// If system tray minimize is disabled, restore() will be called every time.
	// Otherwise, window is restored or minimized
	if(!allowSysTrayMinimize || isHidden() || isMinimized())
		restore();
	else
		minimize();
}

void lmcMainWindow::setTrayTooltip(void) {
	if(bConnected)
		pTrayIcon->setToolTip(lmcStrings::appName());
	else {
		QString msg = tr("%1 - Not Connected");
		pTrayIcon->setToolTip(msg.arg(lmcStrings::appName()));
	}
}

// ===================== Inline Chat Implementation =====================

void lmcMainWindow::initInlineChat(void) {
	pInlineMessageLog = new lmcMessageLog(ui.wgtChatLog);
	ui.logLayout->addWidget(pInlineMessageLog);

	connect(ui.txtChatMessage, SIGNAL(returnPressed()), this, SLOT(inlineSendMessage()));

	// Create smiley menu
	pInlineSmileyMenu = new QMenu(this);
	pInlineSmileyAction = new lmcImagePickerAction(this, smileyPic, SM_COUNT, 20, 12, &nSmiley);
	connect(pInlineSmileyAction, SIGNAL(triggered()), this, SLOT(inlineSmileyAction_triggered()));
	pInlineSmileyMenu->addAction(pInlineSmileyAction);

	// Create toolbar for inline chat
	QToolBar* pChatBar = new QToolBar(ui.wgtChatToolBar);
	pChatBar->setIconSize(QSize(20, 20));
	pChatBar->setStyleSheet("QToolBar { border: 0px; padding: 0px; spacing: 2px; background: transparent; }");
	ui.chatToolBarInner->addWidget(pChatBar);

	pInlineFontAction = pChatBar->addAction(QIcon(QPixmap(IDR_FONT, "PNG")), tr("Font"), this, SLOT(btnFont_clicked()));
	pInlineFontColorAction = pChatBar->addAction(QIcon(QPixmap(IDR_FONTCOLOR, "PNG")), tr("Font Color"), this, SLOT(btnFontColor_clicked()));
	pChatBar->addSeparator();
	pInlineFileAction = pChatBar->addAction(QIcon(QPixmap(IDR_FILE, "PNG")), tr("Send File"), this, SLOT(btnFile_clicked()));
	pInlineFolderAction = pChatBar->addAction(QIcon(QPixmap(IDR_FOLDER, "PNG")), tr("Send Folder"), this, SLOT(btnFolder_clicked()));
	pChatBar->addSeparator();

	QToolButton* pSmileyButton = new QToolButton(pChatBar);
	pSmileyButton->setIcon(QIcon(QPixmap(IDR_SMILEY, "PNG")));
	pSmileyButton->setMenu(pInlineSmileyMenu);
	pSmileyButton->setPopupMode(QToolButton::InstantPopup);
	pChatBar->addWidget(pSmileyButton);
	pSmileyButton->setAutoRaise(false);

	pInlineMessageLog->installEventFilter(this);
	ui.txtChatMessage->installEventFilter(this);

	// Add send button next to the inline chat message input
	QWidget* parentW = ui.txtChatMessage->parentWidget();
	QVBoxLayout* parentLayoutInl = qobject_cast<QVBoxLayout*>(parentW->layout());
	if (parentLayoutInl) {
		int msgIdxInl = -1;
		for (int i = 0; i < parentLayoutInl->count(); ++i) {
			if (parentLayoutInl->itemAt(i)->widget() == ui.txtChatMessage) {
				msgIdxInl = i;
				break;
			}
		}
		if (msgIdxInl >= 0) {
			QLayoutItem* msgItemInl = parentLayoutInl->takeAt(msgIdxInl);
			QHBoxLayout* sendLayoutInl = new QHBoxLayout();
			sendLayoutInl->setContentsMargins(0, 0, 0, 0);
			sendLayoutInl->setSpacing(0);
			sendLayoutInl->addWidget(ui.txtChatMessage, 1);
			QToolButton* btnSendInl = new QToolButton();
			btnSendInl->setObjectName("btnSend");
			btnSendInl->setFixedSize(36, 36);
			btnSendInl->setCursor(Qt::PointingHandCursor);
			btnSendInl->setText(QString::fromUtf8("\xe2\x9e\xa4"));
			QFont sendFontInl = btnSendInl->font();
			sendFontInl.setPointSize(14);
			btnSendInl->setFont(sendFontInl);
			btnSendInl->setToolTip(tr("Send"));
			sendLayoutInl->addWidget(btnSendInl);
			parentLayoutInl->insertLayout(msgIdxInl, sendLayoutInl);
			delete msgItemInl;
			connect(btnSendInl, &QToolButton::clicked, this, &lmcMainWindow::inlineSendMessage);
		}
	}

	inlineLocalId = QString();
	inlinePeerId = QString();
	inlinePeerName = QString();
	inlineMessageColor = QColor("#ffffff");
	inlineShowSmiley = true;
	ui.txtChatMessage->setStyleSheet("QTextEdit {color: #ffffff;}");
	inlineFontSizeVal = 0;
	currentChatPeer = QString();

	lblMsgCount = new QLabel(ui.chatHeader);
	lblMsgCount->setObjectName("lblMsgCount");
	lblMsgCount->setStyleSheet("QLabel { color: #8e9297; font-size: 11pt; font-weight: bold; }");
	lblMsgCount->setToolTip(tr("Total chats"));
	lblMsgCount->setText("0");
	ui.chatHeaderLayout->addWidget(lblMsgCount);
}

void lmcMainWindow::showInlineChat(QString* lpszUserId) {
	if(!lpszUserId || lpszUserId->isEmpty())
		return;

	// Don't re-show same chat
	if(currentChatPeer == *lpszUserId && ui.rightPanel->currentIndex() == 1)
		return;

	// Save current conversation's message log to cache before switching
	if(!currentChatPeer.isEmpty() && pInlineMessageLog->hasData) {
		QString cacheFile = QDir(StdLocation::cacheDir()).absoluteFilePath("msg_" + currentChatPeer + ".tmp");
		pInlineMessageLog->saveMessageLog(cacheFile);
	}

	QTreeWidgetItem* pItem = getUserItem(lpszUserId);
	if(!pItem) {
		ui.rightPanel->setCurrentIndex(0);
		return;
	}

	// Clear unread count for this user
	pItem->setData(0, UnreadRole, 0);
	ui.tvUserList->update();

	QString userName = pItem->text(0);
	int statusIndex = pItem->data(0, StatusRole).toInt();
	QString statusText = lmcStrings::statusDesc()[statusIndex];
	QString avatarPath;

	// Set up header
	ui.lblChatName->setText(userName);
	ui.lblChatStatus->setText(statusText);

	// Set avatar
	QVariant avatarVar = pItem->data(0, AvatarRole);
	if(!avatarVar.isNull()) {
		QPixmap avatarPix = avatarVar.value<QIcon>().pixmap(32, 32);
		ui.chatAvatar->setPixmap(avatarPix);
	} else {
		QPixmap defaultAvatar(AVT_DEFAULT);
		ui.chatAvatar->setPixmap(defaultAvatar.scaled(32, 32, Qt::KeepAspectRatio, Qt::SmoothTransformation));
	}

	// Set up message log
	inlinePeerId = *lpszUserId;
	inlinePeerName = userName;
	inlineLocalId = pLocalUser->id;
	currentChatPeer = *lpszUserId;

	pInlineMessageLog->localId = inlineLocalId;
	pInlineMessageLog->peerId = inlinePeerId;
	pInlineMessageLog->peerName = inlinePeerName;
	pInlineMessageLog->participantAvatars.clear();
	pInlineMessageLog->participantAvatars.insert(inlineLocalId, pLocalUser->avatarPath);
	pInlineMessageLog->participantAvatars.insert(inlinePeerId, avatarPath);

	// Load the theme and clear message log for fresh conversation
	QString themePath = pSettings->value(IDS_THEME, IDS_THEME_VAL).toString();
	pInlineMessageLog->initMessageLog(themePath);

	// Try to restore any saved message log
	QString cacheFile = QDir(StdLocation::cacheDir()).absoluteFilePath("msg_" + inlinePeerId + ".tmp");
	pInlineMessageLog->restoreMessageLog(cacheFile);

	updateMsgCount();

	// Show the chat page
	ui.rightPanel->setCurrentIndex(1);
	ui.txtChatMessage->setFocus();
}

void lmcMainWindow::inlineReceiveMessage(QString* lpszUserId, QString* lpszUserName, MessageType type, XmlMessage* pMessage) {
	if(!lpszUserId || *lpszUserId == pLocalUser->id)
		return;

	if(currentChatPeer != *lpszUserId) {
		// Message is for a different user — increment unread count
		if(type == MT_Message || type == MT_File || type == MT_Folder) {
			QTreeWidgetItemIterator it(ui.tvUserList);
			while(*it) {
				if((*it)->data(0, TypeRole).toString() == "User" &&
					(*it)->data(0, IdRole).toString() == *lpszUserId) {
					int count = (*it)->data(0, UnreadRole).toInt() + 1;
					(*it)->setData(0, UnreadRole, count);
					break;
				}
				++it;
			}
		}
		return;
	}

	QString senderId = lpszUserId ? *lpszUserId : inlineLocalId;
	QString senderName = lpszUserName ? *lpszUserName : inlinePeerName;
	QString data;

	switch(type) {
	case MT_Message:
	case MT_PublicMessage:
	case MT_GroupMessage:
		appendInlineMessageLog(type, lpszUserId, &senderName, pMessage);
		if(isHidden() || !isActiveWindow()) {
			pSoundPlayer->play(SE_NewMessage);
		}
		break;
	case MT_Broadcast:
		appendInlineMessageLog(type, lpszUserId, &senderName, pMessage);
		break;
	case MT_ChatState:
		appendInlineMessageLog(type, lpszUserId, &senderName, pMessage);
		break;
	case MT_Status:
		data = pMessage->data(XN_STATUS);
		{
			int statusIndex = Helper::statusIndexFromCode(data);
			if(statusIndex != -1) {
				QString statusText = lmcStrings::statusDesc()[statusIndex];
				ui.lblChatStatus->setText(statusText);
			}
		}
		break;
	case MT_Avatar:
		data = pMessage->data(XN_FILEPATH);
		pInlineMessageLog->updateAvatar(&senderId, &data);
		break;
	case MT_UserName:
		data = pMessage->data(XN_NAME);
		inlinePeerName = data;
		pInlineMessageLog->updateUserName(&senderId, &data);
		ui.lblChatName->setText(data);
		break;
	case MT_Failed:
		appendInlineMessageLog(type, lpszUserId, &senderName, pMessage);
		break;
	case MT_File:
	case MT_Folder:
		appendInlineMessageLog(type, lpszUserId, &senderName, pMessage);
		break;
	default:
		break;
	}

	updateMsgCount();
}

void lmcMainWindow::inlineSendMessage(void) {
	QString message = ui.txtChatMessage->toPlainText();
	if(message.trimmed().isEmpty())
		return;

	QFont font = pInlineMessageLog->font();
	font.fromString(pSettings->value(IDS_FONT, IDS_FONT_VAL).toString());

	encodeInlineMessage(&message);

	QDateTime time = QDateTime::currentDateTime();
	XmlMessage xmlMessage;
	xmlMessage.addData(XN_MESSAGE, message);
	xmlMessage.addData(XN_FONT, font.toString());
	xmlMessage.addData(XN_COLOR, inlineMessageColor.name());
	xmlMessage.addHeader(XN_TIME, QString::number(time.toMSecsSinceEpoch()));

	// Append to local message log
	appendInlineMessageLog(MT_Message, &inlineLocalId, &pLocalUser->name, &xmlMessage);

	// Send through the network
	sendMessage(MT_Message, &inlinePeerId, &xmlMessage);

	updateMsgCount();

	ui.txtChatMessage->clear();
	ui.txtChatMessage->setFocus();
}

void lmcMainWindow::inlineSmileyAction_triggered(void) {
	QString smiley = smileyCode[nSmiley];
	ui.txtChatMessage->insertPlainText(smiley);
	ui.txtChatMessage->setFocus();
}

void lmcMainWindow::btnFont_clicked(void) {
	QFont font = pInlineMessageLog->font();
	font.fromString(pSettings->value(IDS_FONT, IDS_FONT_VAL).toString());
	bool ok;
	QFont result = QFontDialog::getFont(&ok, font, this, tr("Select Font"));
	if(ok) {
		pSettings->setValue(IDS_FONT, result.toString());
		pInlineMessageLog->setFont(result);
	}
}

void lmcMainWindow::btnFontColor_clicked(void) {
	QColor color = QColorDialog::getColor(inlineMessageColor, this, tr("Select Font Color"));
	if(color.isValid()) {
		inlineMessageColor = color;
		pSettings->setValue(IDS_COLOR, color.name());
		ui.txtChatMessage->setStyleSheet("QTextEdit {color: " + inlineMessageColor.name() + ";}");
	}
}

void lmcMainWindow::btnFile_clicked(void) {
	if(currentChatPeer.isEmpty())
		return;
	QString dir = pSettings->value(IDS_OPENPATH, IDS_OPENPATH_VAL).toString();
	QString fileName = QFileDialog::getOpenFileName(this, QString(), dir);
	if(!fileName.isEmpty()) {
		pSettings->setValue(IDS_OPENPATH, QFileInfo(fileName).dir().absolutePath());
		sendMessage(MT_File, &currentChatPeer, &fileName);
	}
}

void lmcMainWindow::btnFolder_clicked(void) {
	if(currentChatPeer.isEmpty())
		return;
	QString dir = pSettings->value(IDS_OPENPATH, IDS_OPENPATH_VAL).toString();
	QString path = QFileDialog::getExistingDirectory(this, QString(), dir, QFileDialog::ShowDirsOnly);
	if(!path.isEmpty()) {
		pSettings->setValue(IDS_OPENPATH, QFileInfo(path).absolutePath());
		sendMessage(MT_Folder, &currentChatPeer, &path);
	}
}

void lmcMainWindow::encodeInlineMessage(QString* lpszMessage) {
	lpszMessage->replace("&", "&amp;");
	lpszMessage->replace("<", "&lt;");
	lpszMessage->replace(">", "&gt;");
	lpszMessage->replace("\"", "&quot;");
	lpszMessage->replace("'", "&apos;");

	if(inlineShowSmiley)
		ChatHelper::encodeSmileys(lpszMessage);
}

void lmcMainWindow::decodeInlineMessage(QString* lpszMessage) {
	Q_UNUSED(lpszMessage);
	// Links and smiley decoding is handled by pInlineMessageLog
}

void lmcMainWindow::appendInlineMessageLog(MessageType type, QString* lpszUserId, QString* lpszUserName, XmlMessage* pMessage) {
	if(type == MT_Message || type == MT_PublicMessage || type == MT_GroupMessage) {
		pInlineMessageLog->appendMessageLog(type, lpszUserId, lpszUserName, pMessage);
	} else if(type == MT_Broadcast) {
		QString message = pMessage->data(XN_BROADCAST);
		QDateTime time = QDateTime::fromMSecsSinceEpoch(pMessage->header(XN_TIME).toLongLong());
		pInlineMessageLog->appendBroadcast(lpszUserId, lpszUserName, &message, &time);
	} else if(type == MT_ChatState) {
		QString message = pMessage->data(XN_CHATSTATE);
		QString caption;
		ChatState chatState = (ChatState)Helper::indexOf(ChatStateNames, CS_Max, message);
		switch(chatState) {
		case CS_Composing:
			caption = tr("%1 is typing...");
			break;
		case CS_Paused:
			caption = tr("%1 has entered text");
			break;
		default:
			break;
		}
		if(!caption.isNull()) {
			ThemeData themeData = lmcTheme::loadTheme(
				pSettings->value(IDS_THEME, IDS_THEME_VAL).toString());
			QString html = themeData.stateMsg;
			html.replace("%iconpath%", "qrc" IDR_BLANK);
			html.replace("%sender%", caption.arg(*lpszUserName));
			html.replace("%message%", "");
			pInlineMessageLog->appendMessageLog(&html, type);
		}
	} else if(type == MT_Failed) {
		ThemeData themeData = lmcTheme::loadTheme(
			pSettings->value(IDS_THEME, IDS_THEME_VAL).toString());
		QString html = themeData.sysMsg;
		QString caption = tr("This message was not delivered to %1:");
		QString message = pMessage->data(XN_MESSAGE);
		QFont font;
		font.fromString(pMessage->data(XN_FONT));
		QColor color = QColor::fromString(pMessage->data(XN_COLOR));
		QString fontStyle = "font-family:\"" + font.family() + "\"; ";
		if(font.italic()) fontStyle.append("font-style:italic; ");
		if(font.bold()) fontStyle.append("font-weight:bold; ");
		fontStyle.append("font-size:" + QString::number(font.pointSize()) + "pt; ");
		fontStyle.append("color:" + color.name() + "; ");
		if(font.strikeOut()) fontStyle.append("text-decoration:line-through; ");
		if(font.underline()) fontStyle.append("text-decoration:underline; ");
		html.replace("%iconpath%", "qrc" IDR_CRITICALMSG);
		html.replace("%sender%", caption.arg(*lpszUserName));
		html.replace("%style%", fontStyle);
		html.replace("%message%", message);
		pInlineMessageLog->appendMessageLog(&html, type);
	}
}

void lmcMainWindow::updateMsgCount(void) {
	if(!pInlineMessageLog || !lblMsgCount)
		return;
	int count = 0;
	int total = pInlineMessageLog->messageCount();
	for(int i = 0; i < total; i++) {
		MessageType type = pInlineMessageLog->messageTypeAt(i);
		if(type == MT_Message || type == MT_GroupMessage || type == MT_PublicMessage ||
		   type == MT_File || type == MT_Folder || type == MT_Broadcast)
			count++;
	}
	lblMsgCount->setText(QString::number(count));
}

// ===================== Custom Title Bar =====================

void lmcMainWindow::titleBarMinimize_clicked(void) {
	setWindowState(windowState() | Qt::WindowMinimized);
}

void lmcMainWindow::titleBarMaximize_clicked(void) {
	if(isMaximized()) {
		setWindowState(windowState() & ~Qt::WindowMaximized);
		ui.btnTitleMaximize->setIcon(QIcon(QPixmap(IDR_NAV_RESTORE)));
	} else {
		setWindowState(windowState() | Qt::WindowMaximized);
		ui.btnTitleMaximize->setIcon(QIcon(QPixmap(IDR_NAV_MAXIMIZE)));
	}
}

void lmcMainWindow::titleBarClose_clicked(void) {
	close();
}

void lmcMainWindow::mousePressEvent(QMouseEvent* pEvent) {
	if(pEvent->button() == Qt::LeftButton) {
		titleBarPressPos = pEvent->pos();
		QWidget* child = childAt(pEvent->pos());
		bool isNavButton = (child == ui.btnTitleMinimize || child == ui.btnTitleMaximize || child == ui.btnTitleClose);
		if(child && ui.titleBar->isAncestorOf(child) && !isNavButton) {
			titleBarDragPos = pEvent->globalPosition().toPoint();
			titleBarDrag = true;
			pEvent->accept();
			return;
		}
	}
	QWidget::mousePressEvent(pEvent);
}

void lmcMainWindow::mouseMoveEvent(QMouseEvent* pEvent) {
	if(titleBarDrag) {
		QPoint delta = pEvent->globalPosition().toPoint() - titleBarDragPos;
		titleBarDragPos = pEvent->globalPosition().toPoint();
		move(pos() + delta);
		pEvent->accept();
		return;
	}
	QWidget::mouseMoveEvent(pEvent);
}

void lmcMainWindow::mouseReleaseEvent(QMouseEvent* pEvent) {
	if(pEvent->button() == Qt::LeftButton && titleBarDrag) {
		QPoint releasePos = pEvent->pos();
		if((releasePos - titleBarPressPos).manhattanLength() < 5) {
			QWidget* child = childAt(pEvent->pos());
			if(child == ui.lblAppIcon) {
				QPoint iconBottomLeft = ui.lblAppIcon->mapToGlobal(QPoint(0, ui.lblAppIcon->height()));
				pMainMenu->exec(iconBottomLeft);
			}
		}
		titleBarDrag = false;
		pEvent->accept();
		return;
	}
	QWidget::mouseReleaseEvent(pEvent);
}

void lmcMainWindow::resizeEvent(QResizeEvent* pEvent) {
	QWidget::resizeEvent(pEvent);
	QPainterPath path;
	path.addRoundedRect(QRectF(rect()), 8, 8);
	setMask(path.toFillPolygon().toPolygon());
}
