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


#include <QMenu>
#include <QAction>
#include <QScrollBar>
#include <QRegularExpression>
#include <QDesktopServices>
#include <QUrl>
#include <QDir>
#include <QFileInfo>
#include <QDateTime>
#include <QLocale>
#include <QApplication>
#include <QClipboard>
#include "messagelog.h"

const QString acceptOp("accept");
const QString declineOp("decline");
const QString cancelOp("cancel");

lmcMessageLog::lmcMessageLog(QWidget *parent) : QScrollArea(parent) {
    contentWidget = new QWidget(this);
    mainLayout = new QVBoxLayout(contentWidget);
    mainLayout->setContentsMargins(0, 0, 0, 0);
    mainLayout->setSpacing(0);
    contentWidget->setLayout(mainLayout);
    setWidget(contentWidget);
    setWidgetResizable(true);
    setVerticalScrollBarPolicy(Qt::ScrollBarAsNeeded);
    setHorizontalScrollBarPolicy(Qt::ScrollBarAlwaysOff);

    QScrollBar *vbar = verticalScrollBar();
    vbar->setStyleSheet(
        "QScrollBar:vertical { background: #1e1e1e; width: 8px; border-radius: 4px; margin: 0; }"
        "QScrollBar::handle:vertical { background: #3a3a3a; border-radius: 4px; min-height: 30px; }"
        "QScrollBar::handle:vertical:hover { background: #555; }"
        "QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical { height: 0; }"
        "QScrollBar::add-page:vertical, QScrollBar::sub-page:vertical { background: none; }"
    );

    connect(vbar, &QScrollBar::rangeChanged, this, [this](int, int max) {
        if(autoScroll)
            verticalScrollBar()->setValue(max);
    });

    createContextMenu();

    participantAvatars.clear();
    hasData = false;
    messageTime = false;
    messageDate = false;
    allowLinks = false;
    pathToLink = false;
    trimMessage = true;
    fontSizeVal = 0;
    sendFileMap.clear();
    receiveFileMap.clear();
    lastId = QString();
    messageLog.clear();
    linkHovered = false;
    outStyle = false;
    autoScroll = true;
}

lmcMessageLog::~lmcMessageLog() {
}

void lmcMessageLog::initMessageLog(QString themePath, bool clearLog) {
    if(clearLog)
        messageLog.clear();

    // Remove all existing message widgets
    for(auto &node : messageNodes) {
        mainLayout->removeWidget(node.widget);
        delete node.widget;
    }
    messageNodes.clear();

    lastId = QString();
    this->themePath = themePath;
    reloadTheme();
}

void lmcMessageLog::reloadTheme()
{
    themeData = lmcTheme::loadTheme(themePath);
    contentWidget->setStyleSheet(
        "QWidget { background: transparent; }"
        "QLabel { background: transparent; }"
        "a { color: #00aff4; text-decoration: none; }"
    );
}

void lmcMessageLog::createContextMenu(void) {
    contextMenu = new QMenu(this);
    copyAction = contextMenu->addAction("&Copy", QKeySequence::Copy, this, SLOT(copyAction_triggered()));
    copyLinkAction = contextMenu->addAction("&Copy Link", this, SLOT(copyLinkAction_triggered()));
    contextMenu->addSeparator();
    selectAllAction = contextMenu->addAction("Select &All", QKeySequence::SelectAll, this,
                            SLOT(selectAllAction_triggered()));
    contentWidget->setContextMenuPolicy(Qt::CustomContextMenu);
    connect(contentWidget, SIGNAL(customContextMenuRequested(QPoint)), this, SLOT(showContextMenu(QPoint)));
}

void lmcMessageLog::appendMessageLog(MessageType type, QString* lpszUserId, QString* lpszUserName, XmlMessage* pMessage,
        bool bReload) {

    if(!pMessage && type != MT_Error)
        return;

    QString message;
    QString html;
    QString caption;
    QDateTime time;
    QFont font;
    QColor color;
    QString fontStyle;
    QString id = QString();
    bool addToLog = true;

    removeMessageLog(MT_ChatState);

    switch(type) {
    case MT_Message:
        time.setMSecsSinceEpoch(pMessage->header(XN_TIME).toLongLong());
        message = pMessage->data(XN_MESSAGE);
        font.fromString(pMessage->data(XN_FONT));
        color = QColor::fromString(pMessage->data(XN_COLOR));
        appendMessage(lpszUserId, lpszUserName, &message, &time, &font, &color);
        lastId = *lpszUserId;
        break;
    case MT_PublicMessage:
    case MT_GroupMessage:
        time.setMSecsSinceEpoch(pMessage->header(XN_TIME).toLongLong());
        message = pMessage->data(XN_MESSAGE);
        font.fromString(pMessage->data(XN_FONT));
        color = QColor::fromString(pMessage->data(XN_COLOR));
        appendPublicMessage(lpszUserId, lpszUserName, &message, &time, &font, &color, type);
        lastId = *lpszUserId;
        break;
    case MT_Broadcast:
        time.setMSecsSinceEpoch(pMessage->header(XN_TIME).toLongLong());
        message = pMessage->data(XN_BROADCAST);
        appendBroadcast(lpszUserId, lpszUserName, &message, &time);
        lastId  = QString();
        break;
    case MT_ChatState:
        message = pMessage->data(XN_CHATSTATE);
        caption = getChatStateMessage((ChatState)Helper::indexOf(ChatStateNames, CS_Max, message));
        if(!caption.isNull()) {
            QString text = caption.arg(*lpszUserName);
            QWidget *w = createSystemMessage(text, type);
            addMsg(w);
            messageNodes.append({w, type, QString()});
        }
        addToLog = false;
        break;
    case MT_Failed:
        message = pMessage->data(XN_MESSAGE);
        font.fromString(pMessage->data(XN_FONT));
        color = QColor::fromString(pMessage->data(XN_COLOR));
        fontStyle = getFontStyle(&font, &color, true);
        decodeMessage(&message);
        caption = tr("This message was not delivered to %1:").arg(*lpszUserName);
        {
            QString msgHtml = "<img src='qrc" IDR_CRITICALMSG "' width='16' height='16'/>&nbsp;<b>" + caption + "</b><br/>"
                "<span style='" + fontStyle + "'>" + message + "</span>";
            html.append(msgHtml);
            QWidget *w = createSystemMessage(html, type);
            addMsg(w);
            messageNodes.append({w, type, QString()});
        }
        lastId  = QString();
        break;
    case MT_Error:
        caption = tr("Your message was not sent.");
        {
            QString msgHtml = "<img src='qrc" IDR_CRITICALMSG "' width='16' height='16'/>&nbsp;" + caption;
            QWidget *w = createSystemMessage(msgHtml, type);
            addMsg(w);
            messageNodes.append({w, type, QString()});
        }
        lastId  = QString();
        addToLog = false;
        break;
	case MT_File:
    case MT_Folder:
        id = getFileTempId(pMessage);
        html = getFileMessageText(type, lpszUserName, pMessage, bReload);
        {
            FileMode fileMode = (FileMode)Helper::indexOf(FileModeNames, FM_Max, pMessage->data(XN_MODE));
            bool isSend = (fileMode == FM_Send);
            QWidget *w = createBubble(isSend, html, "", type, id);
            addMsg(w);
            messageNodes.append({w, type, id});
        }
        lastId = QString();
        break;
    case MT_Join:
    case MT_Leave:
        message = pMessage->data(XN_GROUPMSGOP);
        caption = getChatRoomMessage((GroupMsgOp)Helper::indexOf(GroupMsgOpNames, GMO_Max, message));
        if(!caption.isNull()) {
            QString msgHtml = caption.arg(*lpszUserName);
            QWidget *w = createSystemMessage(msgHtml, type);
            addMsg(w);
            messageNodes.append({w, type, QString()});
        }
        lastId = QString();
    default:
        break;
    }

    if(!bReload && addToLog && pMessage) {
        XmlMessage xmlMessage = pMessage->clone();
        QString userId = lpszUserId ? *lpszUserId : QString();
        QString userName = lpszUserName ? *lpszUserName : QString();
        messageLog.append(SingleMessage(type, userId, userName, xmlMessage, id));
    }

    if(autoScroll)
        scrollToEnd();
}

void lmcMessageLog::updateFileMessage(FileMode mode, FileOp op, QString fileId)
{
    QString tempId = getFileTempId(mode, fileId);

    // update the entry in message log
    for(int index = 0; index < messageLog.count(); index++) {
        SingleMessage msg = messageLog[index];
        if(tempId.compare(msg.id) == 0) {
            XmlMessage xmlMessage = msg.message;
            xmlMessage.removeData(XN_FILEOP);
            xmlMessage.addData(XN_FILEOP, FileOpNames[op]);
            msg.message = xmlMessage;
            QString html = getFileMessageText(msg.type, &msg.userName, &msg.message);

            // Extract links from html
            QString linksHtml = "";
            if(html.contains("%links%")) {
                int linksIdx = html.indexOf("%links%");
                linksHtml = html.mid(linksIdx + 7);
            }

            FileMode msgMode = (FileMode)Helper::indexOf(FileModeNames, FM_Max, xmlMessage.data(XN_MODE));
            replaceFileMessage(tempId, xmlMessage.data(XN_FILEID), msgMode, op,
                xmlMessage.data(XN_FILENAME), xmlMessage.data(XN_FILESIZE).toLongLong(),
                msg.userName, linksHtml);
            break;
        }
    }
}

void lmcMessageLog::updateUserName(QString* lpszUserId, QString* lpszUserName) {
    // update the entries in message log
    for(int index = 0; index < messageLog.count(); index++) {
        SingleMessage msg = messageLog.takeAt(index);
        if(lpszUserId->compare(msg.userId) == 0)
            msg.userName = *lpszUserName;
        messageLog.insert(index, msg);
    }

    reloadMessageLog();
}

void lmcMessageLog::updateAvatar(QString* lpszUserId, QString* lpszFilePath) {
    participantAvatars.insert(*lpszUserId, *lpszFilePath);
    reloadMessageLog();
}

void lmcMessageLog::reloadMessageLog(void) {
    initMessageLog(themePath, false);
    for(int index = 0; index < messageLog.count(); index++) {
        SingleMessage msg = messageLog[index];
        appendMessageLog(msg.type, &msg.userId, &msg.userName, &msg.message, true);
    }
}

int lmcMessageLog::messageCount(void) const {
    return messageLog.count();
}

MessageType lmcMessageLog::messageTypeAt(int index) const {
    if(index < 0 || index >= messageLog.count())
        return MT_Blank;
    return messageLog.at(index).type;
}

QString lmcMessageLog::prepareMessageLogForSave(OutputFormat format) {
    QDateTime time;

    if(format == HtmlFormat) {
        QString html =
            "<html><head><style type='text/css'>"\
            "*{font-size: 9pt;} body {-webkit-nbsp-mode: space; word-wrap: break-word;}"\
            "span.salutation {float:left; font-weight: bold;} span.time {float: right;}"\
            "span.message {clear: both; display: block;} p {border-bottom: 1px solid #CCC;}"\
            "</style></head><body>";

        for(int index = 0; index < messageLog.count(); index++) {
            SingleMessage msg = messageLog.at(index);
            if(msg.type == MT_Message || msg.type == MT_GroupMessage) {
                time.setMSecsSinceEpoch(msg.message.header(XN_TIME).toLongLong());
                QString messageText = msg.message.data(XN_MESSAGE);
                decodeMessage(&messageText, true);
                QString htmlMsg =
                    "<p><span class='salutation'>" + msg.userName + ":</span>"\
                    "<span class='time'>" + QLocale().toString(time.time(), QLocale::ShortFormat) + "</span>"\
                    "<span class='message'>" + messageText + "</span></p>";
                html.append(htmlMsg);
            }
        }

        html.append("</body></html>");
        return html;
    } else {
        QString text;
        for(int index = 0; index < messageLog.count(); index++) {
            SingleMessage msg = messageLog.at(index);
            if(msg.type == MT_Message || msg.type == MT_GroupMessage) {
                time.setMSecsSinceEpoch(msg.message.header(XN_TIME).toLongLong());
                QString textMsg =
                    msg.userName + " [" + QLocale().toString(time.time(), QLocale::ShortFormat) + "]:\n" +
                    msg.message.data(XN_MESSAGE) + "\n\n";
                text.append(textMsg);
            }
        }

        return text;
    }
}

void lmcMessageLog::setAutoScroll(bool enable) {
    autoScroll = enable;
}

void lmcMessageLog::abortPendingFileOperations(void) {
    QMap<QString, XmlMessage>::iterator sIndex = sendFileMap.begin();
    while(sIndex != sendFileMap.end()) {
        XmlMessage fileData = sIndex.value();
        FileOp fileOp = (FileOp)Helper::indexOf(FileOpNames, FO_Max, fileData.data(XN_FILEOP));
        if(fileOp == FO_Request) {
            updateFileMessage(FM_Send, FO_Abort, fileData.data(XN_FILEID));
            sIndex.value().removeData(XN_FILEOP);
            sIndex.value().addData(XN_FILEOP, FileOpNames[FO_Abort]);
        }
        sIndex++;
    }
    QMap<QString, XmlMessage>::iterator rIndex = receiveFileMap.begin();
    while(rIndex != receiveFileMap.end()) {
        XmlMessage fileData = rIndex.value();
        FileOp fileOp = (FileOp)Helper::indexOf(FileOpNames, FO_Max, fileData.data(XN_FILEOP));
        if(fileOp == FO_Request) {
            updateFileMessage(FM_Receive, FO_Abort, fileData.data(XN_FILEID));
            rIndex.value().removeData(XN_FILEOP);
            rIndex.value().addData(XN_FILEOP, FileOpNames[FO_Abort]);
        }
        rIndex++;
    }
}

void lmcMessageLog::saveMessageLog(QString filePath) {
    if(messageLog.isEmpty())
        return;

    QDir dir = QFileInfo(filePath).dir();
    if(!dir.exists())
        dir.mkpath(dir.absolutePath());

    QFile file(filePath);
    if(!file.open(QIODevice::WriteOnly))
        return;

    QDataStream stream(&file);
    stream << peerId << peerName << messageLog;

    file.close();
}

void lmcMessageLog::restoreMessageLog(QString filePath, bool reload) {
    messageLog.clear();

    QFile file(filePath);
    if(!file.open(QIODevice::ReadOnly))
        return;

    QDataStream stream(&file);
    stream >> peerId >> peerName >> messageLog;

    file.close();

    if(reload)
        reloadMessageLog();
}

void lmcMessageLog::resizeEvent(QResizeEvent *event)
{
    QScrollArea::resizeEvent(event);
}

void lmcMessageLog::addMsg(QWidget *w, bool sameSource)
{
    int topMargin = 5;
    if(messageNodes.isEmpty())
        topMargin = 0;
    else if(sameSource)
        topMargin = 2;
    w->setContentsMargins(0, topMargin, 0, 0);
    mainLayout->addWidget(w);
}

QWidget* lmcMessageLog::createBubble(bool isOutgoing,
        const QString &messageHtml, const QString &timestamp,
        MessageType type, const QString &id)
{
    Q_UNUSED(id);
    QColor bgColor = isOutgoing ? QColor("#f0c644") : QColor("#40444b");
    QColor textColor = isOutgoing ? QColor("#000000") : QColor("#dcddde");
    QString timestampColor = isOutgoing ? "rgba(0,0,0,0.45)" : "rgba(255,255,255,0.4)";

    QFrame *bubble = new QFrame();
    bubble->setMaximumWidth(500);
    bubble->setStyleSheet(QString(
        "QFrame { background-color: %1; border-radius: 2px; padding: 2px; }"
    ).arg(bgColor.name()));

    QVBoxLayout *bubbleLayout = new QVBoxLayout(bubble);
    bubbleLayout->setContentsMargins(2, 2, 2, 2);
    bubbleLayout->setSpacing(1);

    QLabel *msgLabel = new QLabel(messageHtml);
    msgLabel->setStyleSheet("font-size: 10pt; color: " + textColor.name() + "; word-wrap: break-word;");
    msgLabel->setTextFormat(Qt::RichText);
    msgLabel->setWordWrap(true);
    msgLabel->setSizePolicy(QSizePolicy::MinimumExpanding, QSizePolicy::Preferred);
    msgLabel->setTextInteractionFlags(Qt::TextSelectableByMouse | Qt::LinksAccessibleByMouse);
    connect(msgLabel, &QLabel::linkActivated, this, &lmcMessageLog::onLinkClicked);
    bubbleLayout->addWidget(msgLabel);

    QLabel *timeLabel = new QLabel(timestamp);
    timeLabel->setStyleSheet("font-size: 7pt; color: " + timestampColor + "; text-align: right;");
    timeLabel->setTextFormat(Qt::PlainText);
    timeLabel->setAlignment(Qt::AlignRight);
    bubbleLayout->addWidget(timeLabel);

    // Outer container for alignment
    QWidget *container = new QWidget();
    QHBoxLayout *hLayout = new QHBoxLayout(container);
    hLayout->setContentsMargins(0, 0, 0, 0);
    hLayout->setSpacing(0);

    if(isOutgoing) {
        hLayout->addStretch();
        hLayout->addWidget(bubble);
    } else {
        hLayout->addWidget(bubble);
        hLayout->addStretch();
    }

    // Consecutive messages from same user have less top margin
    container->setProperty("isOutgoing", isOutgoing);
    container->setProperty("messageType", type);

    return container;
}

QWidget* lmcMessageLog::createSystemMessage(const QString &html, MessageType type)
{
    QLabel *label = new QLabel(html);
    label->setStyleSheet("font-size: 9pt; color: #8e9297; text-align: center; padding: 4px 0;");
    label->setTextFormat(Qt::RichText);
    label->setWordWrap(true);
    label->setAlignment(Qt::AlignCenter);
    label->setTextInteractionFlags(Qt::TextSelectableByMouse | Qt::LinksAccessibleByMouse);
    connect(label, &QLabel::linkActivated, this, &lmcMessageLog::onLinkClicked);

    QWidget *container = new QWidget();
    QHBoxLayout *hLayout = new QHBoxLayout(container);
    hLayout->setContentsMargins(0, 0, 0, 0);
    hLayout->addWidget(label);
    container->setProperty("messageType", type);
    return container;
}

QWidget* lmcMessageLog::createFileMessage(const QString &fileId, FileMode mode, FileOp op,
        const QString &fileName, qint64 fileSize,
        const QString &senderName, const QString &linksHtml)
{
    bool isSend = (mode == FM_Send);
    QColor bgColor = isSend ? QColor("#f0c644") : QColor("#40444b");
    QColor textColor = isSend ? QColor("#000000") : QColor("#dcddde");

    QFrame *bubble = new QFrame();
    bubble->setMaximumWidth(500);
    bubble->setStyleSheet(QString(
        "QFrame { background-color: %1; border-radius: 2px; padding: 2px; }"
    ).arg(bgColor.name()));

    QVBoxLayout *bubbleLayout = new QVBoxLayout(bubble);
    bubbleLayout->setContentsMargins(2, 2, 2, 2);
    bubbleLayout->setSpacing(1);

    QString caption;
    if(isSend) {
        caption = tr("Sending '%1' to %2.").arg(fileName, senderName);
    } else {
        if(autoFile)
            caption = tr("%1 is sending you a file:").arg(senderName);
        else
            caption = tr("%1 sends you a file:").arg(senderName);
    }

    QString fileHtml = QString(
        "<table cellpadding='0' cellspacing='0' border='0'><tr>"
        "<td><img src='qrc" IDR_FILEMSG "' width='16' height='16'/></td>"
        "<td style='padding-left:4px;'><b>%1</b><br/>%2 (%3)</td>"
        "</tr></table>"
    ).arg(caption, fileName, Helper::formatSize(fileSize));

    QLabel *msgLabel = new QLabel(fileHtml);
    msgLabel->setStyleSheet("font-size: 10pt; color: " + textColor.name() + ";");
    msgLabel->setTextFormat(Qt::RichText);
    msgLabel->setWordWrap(true);
    msgLabel->setTextInteractionFlags(Qt::TextSelectableByMouse | Qt::LinksAccessibleByMouse);
    connect(msgLabel, &QLabel::linkActivated, this, &lmcMessageLog::onLinkClicked);
    bubbleLayout->addWidget(msgLabel);

    if(!linksHtml.isEmpty()) {
        QLabel *linksLabel = new QLabel(linksHtml);
        linksLabel->setStyleSheet("font-size: 9pt; margin-top: 4px;");
        linksLabel->setTextFormat(Qt::RichText);
        linksLabel->setTextInteractionFlags(Qt::LinksAccessibleByMouse);
        connect(linksLabel, &QLabel::linkActivated, this, &lmcMessageLog::onLinkClicked);
        bubbleLayout->addWidget(linksLabel);
    }

    QWidget *container = new QWidget();
    QHBoxLayout *hLayout = new QHBoxLayout(container);
    hLayout->setContentsMargins(0, 0, 0, 0);
    if(isSend) {
        hLayout->addStretch();
        hLayout->addWidget(bubble);
    } else {
        hLayout->addWidget(bubble);
        hLayout->addStretch();
    }
    container->setProperty("fileId", fileId);
    return container;
}

void lmcMessageLog::replaceFileMessage(const QString &id, const QString &fileId, FileMode mode, FileOp op,
        const QString &fileName, qint64 fileSize,
        const QString &senderName, const QString &linksHtml)
{
    Q_UNUSED(fileId);
    Q_UNUSED(op);
    Q_UNUSED(fileName);
    Q_UNUSED(fileSize);
    Q_UNUSED(linksHtml);
    int idx = indexOfMessageNode(id);
    if(idx < 0) return;

    MessageNode &oldNode = messageNodes[idx];
    mainLayout->removeWidget(oldNode.widget);
    delete oldNode.widget;

    // Rebuild HTML using stored message data
    SingleMessage &msg = messageLog[idx];
    QString html = getFileMessageText(msg.type, &msg.userName, &msg.message);
    bool isSend = (mode == FM_Send);
    QWidget *w = createBubble(isSend, html, "", msg.type, id);
    mainLayout->insertWidget(idx, w);
    messageNodes[idx].widget = w;

    if(autoScroll)
        scrollToEnd();
}

int lmcMessageLog::indexOfMessageNode(const QString &id) const
{
    for(int i = 0; i < messageNodes.size(); i++) {
        if(messageNodes[i].id == id)
            return i;
    }
    return -1;
}

void lmcMessageLog::removeMessageLog(MessageType type) {
    for(int i = messageNodes.size() - 1; i >= 0; i--) {
        if(messageNodes[i].type == type) {
            mainLayout->removeWidget(messageNodes[i].widget);
            delete messageNodes[i].widget;
            messageNodes.removeAt(i);
        }
    }
}

void lmcMessageLog::appendMessageLog(QString *lpszHtml, MessageType type, const QString &id) {
    QWidget *w = createSystemMessage(*lpszHtml, type);
    addMsg(w);
    messageNodes.append({w, type, id});

    if(autoScroll)
        scrollToEnd();
}

void lmcMessageLog::setHtml(const QString &html) {
    // Clear existing widgets
    for(auto &node : messageNodes) {
        mainLayout->removeWidget(node.widget);
        delete node.widget;
    }
    messageNodes.clear();

    // Create a single rich-text label with the HTML content
    QLabel *label = new QLabel(html);
    label->setStyleSheet("font-size: 9pt; color: #dcddde; padding: 8px;");
    label->setTextFormat(Qt::RichText);
    label->setWordWrap(true);
    label->setTextInteractionFlags(Qt::TextSelectableByMouse | Qt::LinksAccessibleByMouse);

    QWidget *container = new QWidget();
    QHBoxLayout *hLayout = new QHBoxLayout(container);
    hLayout->setContentsMargins(0, 0, 0, 0);
    hLayout->addWidget(label);

    addMsg(container);
    messageNodes.append({container, MT_Blank, QString()});

    if(autoScroll)
        scrollToEnd();
}

void lmcMessageLog::appendBroadcast(QString* lpszUserId, QString* lpszUserName, QString* lpszMessage, QDateTime* pTime) {
    Q_UNUSED(lpszUserId);

    decodeMessage(lpszMessage);

    QString caption = tr("Broadcast message from %1:").arg(*lpszUserName);
    QString html = "<table cellpadding='0' cellspacing='0' border='0'><tr>"
        "<td><img src='qrc" IDR_BROADCASTMSG "' width='16' height='16'/></td>"
        "<td style='padding-left:4px;'><b>" + caption + "</b><br/>" + *lpszMessage + "</td>"
        "</tr></table>";

    QLabel *label = new QLabel(html);
    label->setStyleSheet("font-size: 10pt; color: #dcddde; padding: 4px 8px;");
    label->setTextFormat(Qt::RichText);
    label->setWordWrap(true);
    label->setTextInteractionFlags(Qt::TextSelectableByMouse | Qt::LinksAccessibleByMouse);
    connect(label, &QLabel::linkActivated, this, &lmcMessageLog::onLinkClicked);

    QWidget *container = new QWidget();
    QHBoxLayout *hLayout = new QHBoxLayout(container);
    hLayout->setContentsMargins(0, 0, 0, 0);
    hLayout->addWidget(label);

    addMsg(container);
    messageNodes.append({container, MT_Broadcast, QString()});

    hasData = true;

    if(autoScroll)
        scrollToEnd();
}

void lmcMessageLog::appendMessage(QString* lpszUserId, QString* lpszUserName, QString* lpszMessage, QDateTime* pTime,
                                  QFont* pFont, QColor* pColor) {
    bool localUser = (lpszUserId->compare(localId) == 0);

    decodeMessage(lpszMessage);

    QString fontStyle = getFontStyle(pFont, pColor, localUser);
    QString timestamp = getTimeString(pTime);

    bool isConsecutive = (lpszUserId->compare(lastId) == 0);
    if(!isConsecutive)
        hasData = true;

    QString msgHtml = "<span style='" + fontStyle + "'>" + *lpszMessage + "</span>";

    QWidget *w = createBubble(localUser, msgHtml, timestamp, MT_Message, QString());
    addMsg(w, isConsecutive);
    messageNodes.append({w, MT_Message, QString()});

    if(autoScroll)
        scrollToEnd();
}

void lmcMessageLog::appendPublicMessage(QString* lpszUserId, QString* lpszUserName, QString* lpszMessage,
                                        QDateTime *pTime, QFont *pFont, QColor *pColor, MessageType messageType) {
    bool localUser = (lpszUserId->compare(localId) == 0);

    decodeMessage(lpszMessage);

    QString fontStyle = getFontStyle(pFont, pColor, localUser);
    QString timestamp = getTimeString(pTime);

    bool isConsecutive = (lpszUserId->compare(lastId) == 0);
    if(!isConsecutive) {
        outStyle = !outStyle;
        hasData = true;
    }

    QString msgHtml = "<span style='" + fontStyle + "'>" + *lpszMessage + "</span>";

    QWidget *w = createBubble(localUser, msgHtml, timestamp, messageType, QString());
    addMsg(w, isConsecutive);
    messageNodes.append({w, messageType, QString()});

    if(autoScroll)
        scrollToEnd();
}

QString lmcMessageLog::getFileMessageText(MessageType type, QString* lpszUserName, XmlMessage* pMessage, bool bReload)
{
    QString html;
    QString caption;
    QString fileId = pMessage->data(XN_FILEID);
    QString szStatus;
    QString fileType;

    switch(type) {
    case MT_File:
        fileType = "file";
        break;
    case MT_Folder:
        fileType = "folder";
        break;
    default:
        throw std::logic_error("lmcMessageLog::generateFileMessageText: not yet implemented");
    }

    html = themeData.reqMsg;
    html.replace("%iconpath%", "qrc" IDR_FILEMSG);

    FileOp fileOp = (FileOp)Helper::indexOf(FileOpNames, FO_Max, pMessage->data(XN_FILEOP));
    FileMode fileMode = (FileMode)Helper::indexOf(FileModeNames, FM_Max, pMessage->data(XN_MODE));

    if(fileMode == FM_Send) {
        caption = tr("Sending '%1' to %2.");
        html.replace("%sender%", caption.arg(pMessage->data(XN_FILENAME), *lpszUserName));
        html.replace("%message%", "");

        switch(fileOp) {
        case FO_Request:
            sendFileMap.insert(fileId, *pMessage);
            html.replace("%links%", "<a href='lmc://" + fileType + "/" + cancelOp + "/" + fileId + "'>" + tr("Cancel") + "</a>");
            break;
        case FO_Cancel:
        case FO_Accept:
        case FO_Decline:
        case FO_Error:
        case FO_Abort:
        case FO_Complete:
            szStatus = getFileStatusMessage(FM_Send, fileOp);
            html.replace("%links%", szStatus);
            break;
        default:
            html = QString();
        }
    } else {
        if(autoFile) {
            if(type == MT_File)
                caption = tr("%1 is sending you a file:");
            else
                caption = tr("%1 is sending you a folder:");
            html.replace("%sender%", caption.arg(*lpszUserName));
            html.replace("%message%", pMessage->data(XN_FILENAME) + " (" +
                Helper::formatSize(pMessage->data(XN_FILESIZE).toLongLong()) + ")");
            html.replace("%fileid%", "");
        } else {
            if(type == MT_File)
                caption = tr("%1 sends you a file:");
            else
                caption = tr("%1 sends you a folder:");
            html.replace("%sender%", caption.arg(*lpszUserName));
            html.replace("%message%", pMessage->data(XN_FILENAME) + " (" +
                Helper::formatSize(pMessage->data(XN_FILESIZE).toLongLong()) + ")");
        }

        switch(fileOp) {
        case FO_Request:
            receiveFileMap.insert(fileId, *pMessage);

            if(autoFile) {
                html.replace("%links%", tr("Accepted"));
                if(!bReload)
                    fileOperation(fileId, acceptOp, fileType);
            } else {
                html.replace("%links%",
                    "<a href='lmc://" + fileType + "/" + acceptOp + "/" + fileId + "'>" + tr("Accept") + "</a>&nbsp;&nbsp;" +
                    "<a href='lmc://" + fileType + "/" + declineOp + "/" + fileId + "'>" + tr("Decline") + "</a>");
            }
            break;
        case FO_Cancel:
        case FO_Accept:
        case FO_Decline:
        case FO_Error:
        case FO_Abort:
        case FO_Complete:
            szStatus = getFileStatusMessage(FM_Receive, fileOp);
            html.replace("%links%", szStatus);
            break;
        default:
            html = QString();
        }
    }

    return html;
}

QString lmcMessageLog::getFontStyle(QFont* pFont, QColor* pColor, bool size) {
    QString style = "font-family:\"" + pFont->family() + "\"; ";
    if(pFont->italic())
        style.append("font-style:italic; ");
    if(pFont->bold())
        style.append("font-weight:bold; ");

    if(size) {
        style.append("font-size:" + QString::number(pFont->pointSize()) + "pt; ");
        style.append("color:" + pColor->name() + "; ");
    }
    else
        style.append(fontStyle[fontSizeVal] + " ");

    if(pFont->strikeOut())
        style.append("text-decoration:line-through; ");
    if(pFont->underline())
        style.append("text-decoration:underline; ");

    return style;
}

QString lmcMessageLog::getFileStatusMessage(FileMode mode, FileOp op) {
    QString message;

    switch(op) {
    case FO_Accept:
        message = (mode == FM_Send) ? tr("Accepted") : tr("Accepted");
        break;
    case FO_Decline:
        message = (mode == FM_Send) ? tr("Declined") : tr("Declined");
        break;
    case FO_Cancel:
        message = (mode == FM_Send) ? tr("Canceled") : tr("Canceled");
        break;
    case FO_Error:
    case FO_Abort:
        message = (mode == FM_Send) ? tr("Interrupted") : tr("Interrupted");
        break;
    case FO_Complete:
        message = (mode == FM_Send) ? tr("Completed") : tr("Completed");
        break;
    default:
        break;
    }

    return message;
}

QString lmcMessageLog::getChatStateMessage(ChatState chatState) {
    QString message = QString();

    switch(chatState) {
    case CS_Composing:
        message = tr("%1 is typing...");
        break;
    case CS_Paused:
        message = tr("%1 has entered text");
        break;
    default:
        break;
    }

    return message;
}

QString lmcMessageLog::getChatRoomMessage(GroupMsgOp op) {
    QString message = QString();

    switch(op) {
    case GMO_Join:
        message = tr("%1 has joined this conversation");
        break;
    case GMO_Leave:
        message = tr("%1 has left this conversation");
        break;
    default:
        break;
    }

    return message;
}

void lmcMessageLog::fileOperation(QString fileId, QString action, QString fileType, FileMode mode) {
    XmlMessage fileData, xmlMessage;

    MessageType type;
    if(fileType.compare("file") == 0)
        type = MT_File;
    else if(fileType.compare("folder") == 0)
        type = MT_Folder;
    else
        return;

    if(action.compare(acceptOp) == 0) {
        fileData = receiveFileMap.value(fileId);
        xmlMessage.addData(XN_MODE, FileModeNames[FM_Receive]);
        xmlMessage.addData(XN_FILETYPE, FileTypeNames[FT_Normal]);
        xmlMessage.addData(XN_FILEOP, FileOpNames[FO_Accept]);
        xmlMessage.addData(XN_FILEID, fileData.data(XN_FILEID));
        xmlMessage.addData(XN_FILEPATH, fileData.data(XN_FILEPATH));
        xmlMessage.addData(XN_FILENAME, fileData.data(XN_FILENAME));
        xmlMessage.addData(XN_FILESIZE, fileData.data(XN_FILESIZE));
    }
    else if(action.compare(declineOp) == 0) {
        fileData = receiveFileMap.value(fileId);
        xmlMessage.addData(XN_MODE, FileModeNames[FM_Receive]);
        xmlMessage.addData(XN_FILETYPE, FileTypeNames[FT_Normal]);
        xmlMessage.addData(XN_FILEOP, FileOpNames[FO_Decline]);
        xmlMessage.addData(XN_FILEID, fileData.data(XN_FILEID));
    }
    else if(action.compare(cancelOp) == 0) {
        if(mode == FM_Receive)
            fileData = receiveFileMap.value(fileId);
        else
            fileData = sendFileMap.value(fileId);
        xmlMessage.addData(XN_MODE, FileModeNames[mode]);
        xmlMessage.addData(XN_FILETYPE, FileTypeNames[FT_Normal]);
        xmlMessage.addData(XN_FILEOP, FileOpNames[FO_Cancel]);
        xmlMessage.addData(XN_FILEID, fileData.data(XN_FILEID));
    }

    emit messageSent(type, &peerId, &xmlMessage);
}

void lmcMessageLog::scrollToEnd()
{
    QScrollBar *scrollBar = verticalScrollBar();
    scrollBar->setValue(scrollBar->maximum());
}

void lmcMessageLog::showContextMenu(const QPoint& pos) {
    QWidget *child = contentWidget->childAt(pos);
    QLabel *label = nullptr;
    if(child) {
        label = child->findChild<QLabel*>();
    }
    copyAction->setEnabled(label && label->hasSelectedText());
    copyLinkAction->setEnabled(linkHovered);
    copyLinkAction->setVisible(false);
    selectAllAction->setEnabled(!messageNodes.isEmpty());
    contextMenu->exec(contentWidget->mapToGlobal(pos));
}

void lmcMessageLog::copyAction_triggered(void) {
    QWidget *focused = QApplication::focusWidget();
    QLabel *label = qobject_cast<QLabel*>(focused);
    if(label) {
        QClipboard *clipboard = QApplication::clipboard();
        clipboard->setText(label->selectedText());
    }
}

void lmcMessageLog::copyLinkAction_triggered(void) {
}

void lmcMessageLog::selectAllAction_triggered(void) {
    QWidget *focused = QApplication::focusWidget();
    QLabel *label = qobject_cast<QLabel*>(focused);
    if(label) {
        label->setSelection(0, label->text().length());
    }
}

void lmcMessageLog::onLinkClicked(const QString &link)
{
    QString linkPath = link;

    if(linkPath.startsWith("file")) {
        linkPath = linkPath.mid(5);
        QDesktopServices::openUrl(QUrl(QDir::toNativeSeparators(linkPath)));
        return;
    } else if(linkPath.startsWith("www")) {
        linkPath.prepend("http://");
        QDesktopServices::openUrl(QUrl(linkPath));
        return;
    } else if(!linkPath.startsWith("lmc")) {
        QDesktopServices::openUrl(QUrl(link));
        return;
    }

    QStringList linkData = linkPath.split("/", Qt::SkipEmptyParts);
    FileMode mode;
    FileOp op;

    if(linkData[2].compare(acceptOp) == 0) {
        mode = FM_Receive;
        op = FO_Accept;
    } else if(linkData[2].compare(declineOp) == 0) {
        mode = FM_Receive;
        op = FO_Decline;
    } else if(linkData[2].compare(cancelOp) == 0) {
        mode = FM_Send;
        op = FO_Cancel;
    } else
        return;

    updateFileMessage(mode, op, linkData[3]);
    fileOperation(linkData[3], linkData[2], linkData[1], mode);
}

// Called when message received, before adding to message log
// The useDefaults parameter is an override flag that will ignore app settings
// while decoding the message. If the flag is set, message is not trimmed,
// smileys are left as text and links will be detected and converted.
void lmcMessageLog::decodeMessage(QString* lpszMessage, bool useDefaults) {
    if(!useDefaults && trimMessage)
        *lpszMessage = lpszMessage->trimmed();

    if(useDefaults || allowLinks) {
        lpszMessage->replace(QRegularExpression("((?:(?:https?|ftp|file)://|www\\.|ftp\\.)[-A-Z0-9+&@#/%=~_|$?!:,.]*[A-Z0-9+&@#/%=~_|$])", QRegularExpression::CaseInsensitiveOption),
                             "<a data-isLink='true' href='\\1'>\\1</a>");
        lpszMessage->replace("<a data-isLink='true' href='www", "<a data-isLink='true' href='http://www");

        if(!useDefaults && pathToLink)
            lpszMessage->replace(QRegularExpression("((\\\\\\\\[\\w-]+\\\\[^\\\\/:*?<>|\"\"]+)((?:\\\\[^\\\\/:*?<>|\"\"]+)*\\\\?)$)"),
                                 "<a data-isLink='true' href='file:\\1'>\\1</a>");
    }

    QString message = QString();
    int index = 0;

    while(index < lpszMessage->length()) {
        int aStart = lpszMessage->indexOf("<a data-isLink='true'", index);
        if(aStart != -1) {
            QString messageSegment = lpszMessage->mid(index, aStart - index);
            processMessageText(&messageSegment, useDefaults);
            message.append(messageSegment);
            index = lpszMessage->indexOf("</a>", aStart) + 4;
            QString linkSegment = lpszMessage->mid(aStart, index - aStart);
            message.append(linkSegment);
        } else {
            QString messageSegment = lpszMessage->mid(index);
            processMessageText(&messageSegment, useDefaults);
            message.append(messageSegment);
            break;
        }
    }

    message.replace("\n", "<br/>");

    *lpszMessage = message;
}

void lmcMessageLog::processMessageText(QString* lpszMessageText, bool useDefaults) {
    ChatHelper::makeHtmlSafe(lpszMessageText);
    if(!useDefaults && showSmiley)
        ChatHelper::decodeSmileys(lpszMessageText);
}

QString lmcMessageLog::getTimeString(QDateTime* pTime) {
    QString szTimeStamp;
    if(messageTime) {
        szTimeStamp.append("(");
        if(messageDate)
            szTimeStamp.append(QLocale().toString(pTime->date(), QLocale::ShortFormat) + "&nbsp;");
        szTimeStamp.append(QLocale().toString(pTime->time(), QLocale::ShortFormat) + ")&nbsp;");
    }

    return szTimeStamp;
}

void lmcMessageLog::setUIText(void) {
    copyAction->setText(tr("&Copy"));
    selectAllAction->setText(tr("Select &All"));
    reloadMessageLog();
}

QString lmcMessageLog::getFileTempId(FileMode mode, QString fileId) const
{
    QString tempId = (mode == FM_Send) ? "send" : "receive";
    tempId.append(fileId);
    return tempId;
}

QString lmcMessageLog::getFileTempId(XmlMessage *pMessage) const
{
    QString fileId = pMessage->data(XN_FILEID);
    FileMode fileMode = (FileMode)Helper::indexOf(FileModeNames, FM_Max, pMessage->data(XN_MODE));
    return getFileTempId(fileMode, fileId);
}
