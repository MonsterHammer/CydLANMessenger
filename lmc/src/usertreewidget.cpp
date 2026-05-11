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


#include "usertreewidget.h"

lmcUserTreeWidgetItem::lmcUserTreeWidgetItem() : QTreeWidgetItem(UserType + 1) {
	//	make item not user checkable
	setFlags(flags() & ~Qt::ItemIsUserCheckable);
}

QRect lmcUserTreeWidgetItem::checkBoxRect(const QRect& itemRect) {
	QRect checkBoxRect(0, 0, 0, 0);

	if(data(0, TypeRole).toString() == "Group")
		checkBoxRect = QRect(itemRect.left(), itemRect.top() + ((itemRect.height() - 12) / 2), 0, 0);
	else if(data(0, TypeRole).toString() == "User")
		checkBoxRect = QRect(itemRect.left(), itemRect.top() + 4, 0, 0);

    lmcUserTreeWidget* treeWidget = static_cast<lmcUserTreeWidget*>(this->treeWidget());
	if(treeWidget->checkable()) {
		checkBoxRect.setSize(QSize(12, 12));
		checkBoxRect.moveLeft(checkBoxRect.left() + 3);
	}

	return checkBoxRect;
}

void lmcUserTreeWidgetGroupItem::addChild(QTreeWidgetItem* child) {
    lmcUserTreeWidget* treeWidget = static_cast<lmcUserTreeWidget*>(this->treeWidget());
	child->setSizeHint(0, QSize(0, itemViewHeight[treeWidget->view()]));
	QTreeWidgetItem::addChild(child);
}

bool lmcUserTreeWidgetUserItem::operator < (const QTreeWidgetItem& other) const {
	int column = treeWidget()->sortColumn();
	if(column == 0) {
		//	sort based on status and user name
		if(data(column, StatusRole).toInt() < other.data(column, StatusRole).toInt())
			return true;
		else if(data(column, StatusRole).toInt() > other.data(column, StatusRole).toInt())
			return false;
		else
			return text(column).toLower() < other.text(column).toLower();
	}

	return text(column).toLower() < other.text(column).toLower();
}

void lmcUserTreeWidgetDelegate::paint(QPainter* painter, const QStyleOptionViewItem& option, const QModelIndex& index) const {
	painter->save();

	static const QColor DARK_BG = QColor("#2f3136");
	static const QColor DARK_BG_ALT = QColor("#2c2e33");
	static const QColor DARK_HOVER = QColor("#32353b");
	static const QColor DARK_SELECTED = QColor("#393c43");
	static const QColor DISCORD_TEXT = QColor("#dcddde");
	static const QColor DISCORD_MUTED = QColor("#8e9297");
	static const QColor DISCORD_HEADER_BG = QColor("#40444b");
	static const QColor DISCORD_HEADER_BORDER = QColor("#35373d");
	static const QColor WHITE = QColor("#ffffff");

	QPalette palette = QApplication::palette();
	QRect itemRect = option.rect;
	lmcUserTreeWidgetItem* pItem = static_cast<lmcUserTreeWidgetItem*>(index.internalPointer());
    lmcUserTreeWidget* pTreeWidget = static_cast<lmcUserTreeWidget*>(pItem->treeWidget());
	QString type = pItem->data(0, TypeRole).toString();
	QString name = pItem->data(0, Qt::DisplayRole).toString();

	int padding = 2;

	if(type == "Group") {
		painter->fillRect(itemRect, DARK_BG);

		QColor fillColor = DISCORD_HEADER_BG;
		QColor borderColor = DISCORD_HEADER_BORDER;
		painter->setPen(QPen(borderColor));
		painter->setBrush(QBrush(fillColor));
		itemRect.adjust(1, 1, -2, -1);
		painter->drawRect(itemRect);

		QRect checkBoxRect = pItem->checkBoxRect(itemRect);
		if(pTreeWidget->checkable())
			drawCheckBox(painter, palette, checkBoxRect, pItem->checkState(0));

		painter->setBrush(QBrush(WHITE));
		painter->setPen(QPen(WHITE));
		QPoint points[3];
		if(option.state.testFlag(QStyle::State_Children) && option.state.testFlag(QStyle::State_Open)) {
			points[0] = QPoint(checkBoxRect.right() + 4, itemRect.top() + ((itemRect.height() - 4) / 2));
			points[1] = QPoint(checkBoxRect.right() + 12, itemRect.top() + ((itemRect.height() - 4) / 2));
			points[2] = QPoint(checkBoxRect.right() + 8, itemRect.top() + ((itemRect.height() - 4) / 2) + 4);
		} else {
			points[0] = QPoint(checkBoxRect.right() + 6, itemRect.top() + ((itemRect.height() - 7) / 2));
			points[1] = QPoint(checkBoxRect.right() + 10, itemRect.top() + ((itemRect.height() - 7) / 2) + 4);
			points[2] = QPoint(checkBoxRect.right() + 6, itemRect.top() + ((itemRect.height() - 7) / 2) + 8);
		}
		painter->drawPolygon(points, 3);

		QFont font = painter->font();
		font.setBold(true);
		font.setPixelSize(11);
		painter->setFont(font);
		int textFlags = Qt::AlignLeft | Qt::AlignVCenter;
		int leftPad = checkBoxRect.width() > 0 ? checkBoxRect.right() + 16 : 16;
		QRect textRect = itemRect.adjusted(leftPad, padding, -5, -padding);
		painter->setPen(QPen(WHITE));
		QString text = painter->fontMetrics().elidedText(name, Qt::ElideRight, textRect.width());
		painter->drawText(textRect, textFlags, text);
	} else if(type == "User") {
		QColor fillColor, borderColor;
		bool isSelected = option.state.testFlag(QStyle::State_Active) && option.state.testFlag(QStyle::State_Enabled)
				&& option.state.testFlag(QStyle::State_Selected);
		bool isHovered = option.state.testFlag(QStyle::State_MouseOver);

		if(isSelected) {
			fillColor = DARK_SELECTED;
			borderColor = DARK_SELECTED;
		} else if(isHovered) {
			fillColor = DARK_HOVER;
			borderColor = DARK_HOVER;
		} else if(index.row() % 2 == 1) {
			fillColor = DARK_BG_ALT;
			borderColor = DARK_BG_ALT;
		} else {
			fillColor = DARK_BG;
			borderColor = DARK_BG;
		}

		painter->setPen(QPen(borderColor));
		painter->setBrush(QBrush(fillColor));
		itemRect.adjust(1, 0, -2, -1);
		painter->drawRect(itemRect);

		QRect checkBoxRect = pItem->checkBoxRect(itemRect);
		if(pTreeWidget->checkable())
			drawCheckBox(painter, palette, checkBoxRect, pItem->checkState(0));

		QPixmap statusImage = pItem->icon(0).pixmap(QSize(16, 16));
		int leftPad = checkBoxRect.width() > 0 ? checkBoxRect.right() + 5 : 5;
		QRect statusRect = itemRect.adjusted(leftPad, padding, 0, 0);
		statusRect.setSize(statusImage.size());
		painter->drawPixmap(statusRect, statusImage);

		QRect avatarRect = itemRect.adjusted(itemRect.width(), padding, 0, 0);
		if(pTreeWidget->view() == ULV_Detailed) {
			QVariant avatar = pItem->data(0, AvatarRole);
			if(!avatar.isNull()) {
				QPixmap avatarImage = ((QIcon)pItem->data(0, AvatarRole).value<QIcon>()).pixmap(32, 32);
				avatarRect.setLeft(avatarRect.right() - avatarImage.width() - padding);
				avatarRect.setSize(avatarImage.size());
				painter->drawPixmap(avatarRect, avatarImage);
			}
		}

		painter->setPen(QPen(DISCORD_TEXT));
		int textFlags = Qt::AlignLeft;
		textFlags |= (pTreeWidget->view() == ULV_Detailed ? Qt::AlignTop : Qt::AlignVCenter);
		QRect textRect = itemRect.adjusted(statusRect.right() + 5, padding, -(5 + avatarRect.width() + padding), -padding);
		QString text = painter->fontMetrics().elidedText(name, Qt::ElideRight, textRect.width());
		painter->drawText(textRect, textFlags, text);

		if(pTreeWidget->view() == ULV_Detailed) {
			QVariant note = pItem->data(0, SubtextRole);
			if(!note.isNull()) {
				QString userNote = note.toString();
                painter->setPen(QPen(DISCORD_MUTED));
				textFlags = Qt::AlignLeft | Qt::AlignBottom;
				text = painter->fontMetrics().elidedText(userNote, Qt::ElideRight, 
textRect.width());
				painter->drawText(textRect, textFlags, text);
			}
		}
	}

	painter->restore();
}

void lmcUserTreeWidgetDelegate::drawCheckBox(QPainter *painter, const QPalette& palette,
										const QRect &checkBoxRect, Qt::CheckState checkState) const {
	static const QColor DARK_BORDER = QColor("#72767d");
	static const QColor DARK_CHECK = QColor("#5865f2");
	painter->setPen(QPen(DARK_BORDER));
	painter->setBrush(QColor("#2f3136"));
	painter->drawRect(checkBoxRect);

	if(checkState == Qt::Checked) {
		painter->setPen(QPen(DARK_CHECK, 1));
		painter->drawLine(checkBoxRect.left() + 2, checkBoxRect.top() + 6, checkBoxRect.left() + 4, checkBoxRect.top() + 8);
		painter->drawLine(checkBoxRect.left() + 2, checkBoxRect.top() + 7, checkBoxRect.left() + 4, checkBoxRect.top() + 9);
		painter->drawLine(checkBoxRect.left() + 2, checkBoxRect.top() + 8, checkBoxRect.left() + 4, checkBoxRect.top() + 10);
		painter->drawLine(checkBoxRect.left() + 4, checkBoxRect.top() + 8, checkBoxRect.left() + 10, checkBoxRect.top() + 2);
		painter->drawLine(checkBoxRect.left() + 4, checkBoxRect.top() + 9, checkBoxRect.left() + 10, checkBoxRect.top() + 3);
		painter->drawLine(checkBoxRect.left() + 4, checkBoxRect.top() + 10, checkBoxRect.left() + 10, checkBoxRect.top() + 4);
	}
}

lmcUserTreeWidget::lmcUserTreeWidget(QWidget* parent) : QTreeWidget(parent) {
	itemDelegate = new lmcUserTreeWidgetDelegate();
	setItemDelegate(itemDelegate);

	isCheckable = false;
	viewType = ULV_Detailed;
}

bool lmcUserTreeWidget::checkable(void) {
	return isCheckable;
}

void lmcUserTreeWidget::setCheckable(bool enable) {
	isCheckable = enable;
}

UserListView lmcUserTreeWidget::view(void) {
	return viewType;
}

void lmcUserTreeWidget::setView(UserListView view) {
	viewType = view;

	//	Set the item heights for the selected view type
	for(int index = 0; index < topLevelItemCount(); index++) {
		QTreeWidgetItem* item = topLevelItem(index);
		for(int childIndex = 0; childIndex < item->childCount(); childIndex++)
			item->child(childIndex)->setSizeHint(0, QSize(0, itemViewHeight[viewType]));
	}
}

void lmcUserTreeWidget::mousePressEvent(QMouseEvent* event) {
	if(event->button() == Qt::LeftButton) {
		QTreeWidgetItem* item = itemAt(event->pos());

		dragGroup = false;
		dragUser = false;
		dragItem = NULL;
		parentId = QString();
		expanded = false;

		if(item) {
			dragItem = item;
			if(dynamic_cast<lmcUserTreeWidgetGroupItem*>(item)) {
				dragGroup = true;
				expanded = dragItem->isExpanded();
			}
			else if(dynamic_cast<lmcUserTreeWidgetUserItem*>(item)) {
				dragUser = true;
				parentId = dragItem->parent()->data(0, IdRole).toString();
			}
		}
	}

	QTreeWidget::mousePressEvent(event);
}

void lmcUserTreeWidget::dragMoveEvent(QDragMoveEvent* event) {
	QTreeWidget::dragMoveEvent(event);

	QTreeWidgetItem* item = itemAt(event->pos());
	bool accept = false;

	if(dragUser) {
		if(item && dynamic_cast<lmcUserTreeWidgetGroupItem*>(item) && visualItemRect(item).contains(event->pos(), true))
			accept = true;
	}
	else if(dragGroup) {
		if(!item || (dynamic_cast<lmcUserTreeWidgetGroupItem*>(item) && !visualItemRect(item).contains(event->pos(), true)))
			accept = true;
	}

	accept ? event->accept() : event->ignore();
}

void lmcUserTreeWidget::dropEvent(QDropEvent* event) {
	QTreeWidget::dropEvent(event);
		
	if(dragUser) {
		if(!dragItem->parent()) {
		//	user item dragged to group level. revert
			for(int index = 0; index < topLevelItemCount(); index++) {
				QTreeWidgetItem* parentItem = topLevelItem(index);
				if(parentItem->data(0, IdRole).toString().compare(parentId) == 0) {
					takeTopLevelItem(indexOfTopLevelItem(dragItem));
					parentItem->addChild(dragItem);
					return;
				}
			}
		}
	}
	else if(dragGroup) {
		dragItem->setExpanded(expanded);
	}

	if(dragItem)
		emit itemDragDropped(dragItem);
}

void lmcUserTreeWidget::contextMenuEvent(QContextMenuEvent* event) {
    QTreeWidget::contextMenuEvent(event);

    QTreeWidgetItem* item = itemAt(event->pos());
    QPoint pos = event->globalPos();
    if(item && event->reason() != QContextMenuEvent::Mouse) {
        QRect itemRect = visualItemRect(item);
        pos = itemRect.bottomLeft();
        pos.ry() += itemRect.height();
        pos = mapToGlobal(pos);
    }

    emit itemContextMenu(item, pos);
}

void lmcUserTreeWidget::mouseReleaseEvent(QMouseEvent* event) {
	QTreeWidget::mouseReleaseEvent(event);

	QPoint pos = event->pos();
    lmcUserTreeWidgetItem* item = static_cast<lmcUserTreeWidgetItem*>(itemAt(pos));
	if(item && checkable() && item->checkBoxRect(visualItemRect(item)).contains(pos)) {
		// toggle checkstate
		if(item->checkState(0) == Qt::Checked)
			item->setCheckState(0, Qt::Unchecked);
		else
			item->setCheckState(0, Qt::Checked);
	}
}

void lmcUserTreeWidget::keyPressEvent(QKeyEvent* event) {
	QTreeWidget::keyPressEvent(event);

	if(event->key() == Qt::Key_Space && selectedItems().count() > 0) {
        lmcUserTreeWidgetItem* item = static_cast<lmcUserTreeWidgetItem*>(selectedItems().at(0));
		if(item && checkable()) {
			// toggle checkstate
			if(item->checkState(0) == Qt::Checked)
				item->setCheckState(0, Qt::Unchecked);
			else
				item->setCheckState(0, Qt::Checked);
		}
	}
}
