"""
Widget Protocol for JARVIS AI Assistant
========================================

This module defines the widget data structures that can be sent from the
Python backend to the SwiftUI frontend to render interactive UI components.

Widget Types:
- link: Opens a URL in the browser
- app_launch: Opens a macOS application
- image: Displays an image with preview
- file_preview: Shows a file with quick look option
- code_block: Syntax-highlighted code with copy button
- confirmation: Yes/No action buttons
- quick_action: Generic action button

Example Usage:
--------------
from agent.models.widgets import Widget, WidgetAction

# Create a link widget
link_widget = Widget.link(
    label="Open Documentation",
    url="https://developer.apple.com/documentation/swiftui",
    icon="safari"
)

# Create an app launch widget
app_widget = Widget.app_launch(
    label="Open Xcode",
    app_name="Xcode",
    icon="hammer"
)

# Create a code block widget
code_widget = Widget.code_block(
    code="print('Hello, World!')",
    language="python"
)

# Convert to dict for JSON serialization
widget_dict = link_widget.to_dict()
"""

from typing import Optional, List, Dict, Any
from dataclasses import dataclass, field, asdict


@dataclass
class WidgetAction:
    """Action data for widgets."""
    # For link type
    url: Optional[str] = None

    # For app_launch type
    app_name: Optional[str] = None
    app_scheme: Optional[str] = None
    app_bundle_id: Optional[str] = None

    # For file types
    file_path: Optional[str] = None
    file_name: Optional[str] = None
    file_type: Optional[str] = None

    # For image type
    image_url: Optional[str] = None
    base64_image: Optional[str] = None
    image_alt: Optional[str] = None

    # For code block
    code: Optional[str] = None
    language: Optional[str] = None

    # For confirmation
    confirm_action: Optional[str] = None
    cancel_action: Optional[str] = None

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary, excluding None values."""
        return {k: v for k, v in asdict(self).items() if v is not None}


@dataclass
class Widget:
    """
    Represents an interactive widget that can be displayed in the chat UI.
    """
    type: str
    label: str
    action: WidgetAction
    icon: Optional[str] = None
    subtitle: Optional[str] = None

    def to_dict(self) -> Dict[str, Any]:
        """Convert widget to dictionary for JSON serialization."""
        result = {
            "type": self.type,
            "label": self.label,
            "action": self.action.to_dict()
        }
        if self.icon:
            result["icon"] = self.icon
        if self.subtitle:
            result["subtitle"] = self.subtitle
        return result

    # Factory methods for common widget types

    @classmethod
    def link(cls, label: str, url: str, icon: str = "link") -> "Widget":
        """Create a link widget that opens a URL in the browser."""
        return cls(
            type="link",
            label=label,
            action=WidgetAction(url=url),
            icon=icon
        )

    @classmethod
    def app_launch(
        cls,
        label: str,
        app_name: Optional[str] = None,
        app_scheme: Optional[str] = None,
        app_bundle_id: Optional[str] = None,
        icon: str = "app.fill"
    ) -> "Widget":
        """Create a widget that launches a macOS application."""
        return cls(
            type="app_launch",
            label=label,
            action=WidgetAction(
                app_name=app_name,
                app_scheme=app_scheme,
                app_bundle_id=app_bundle_id
            ),
            icon=icon
        )

    @classmethod
    def image(
        cls,
        label: str,
        image_url: Optional[str] = None,
        base64_image: Optional[str] = None,
        alt: Optional[str] = None
    ) -> "Widget":
        """Create an image widget."""
        return cls(
            type="image",
            label=label,
            action=WidgetAction(
                image_url=image_url,
                base64_image=base64_image,
                image_alt=alt
            )
        )

    @classmethod
    def file_preview(
        cls,
        label: str,
        file_path: str,
        file_name: Optional[str] = None,
        file_type: Optional[str] = None
    ) -> "Widget":
        """Create a file preview widget."""
        # Auto-detect file type from path if not provided
        if not file_type and file_path:
            file_type = file_path.split(".")[-1] if "." in file_path else None
        if not file_name and file_path:
            file_name = file_path.split("/")[-1]

        return cls(
            type="file_preview",
            label=label,
            action=WidgetAction(
                file_path=file_path,
                file_name=file_name,
                file_type=file_type
            )
        )

    @classmethod
    def code_block(
        cls,
        code: str,
        language: str = "plaintext",
        label: str = "Code"
    ) -> "Widget":
        """Create a code block widget with copy functionality."""
        return cls(
            type="code_block",
            label=label,
            action=WidgetAction(code=code, language=language)
        )

    @classmethod
    def confirmation(
        cls,
        label: str,
        confirm_text: str = "Confirm",
        cancel_text: str = "Cancel"
    ) -> "Widget":
        """Create a confirmation widget with Yes/No buttons."""
        return cls(
            type="confirmation",
            label=label,
            action=WidgetAction(
                confirm_action=confirm_text,
                cancel_action=cancel_text
            )
        )

    @classmethod
    def quick_action(
        cls,
        label: str,
        icon: Optional[str] = None,
        subtitle: Optional[str] = None,
        url: Optional[str] = None
    ) -> "Widget":
        """Create a quick action button widget."""
        return cls(
            type="quick_action",
            label=label,
            action=WidgetAction(url=url),
            icon=icon,
            subtitle=subtitle
        )


def widgets_to_list(widgets: List[Widget]) -> List[Dict[str, Any]]:
    """Convert a list of widgets to a list of dictionaries."""
    return [w.to_dict() for w in widgets]


# Response helper for building responses with widgets
@dataclass
class WidgetResponse:
    """Helper class for building responses with widgets."""
    text: str
    widgets: List[Widget] = field(default_factory=list)
    images: List[Dict[str, str]] = field(default_factory=list)

    def add_widget(self, widget: Widget) -> "WidgetResponse":
        """Add a widget to the response."""
        self.widgets.append(widget)
        return self

    def add_link(self, label: str, url: str, icon: str = "link") -> "WidgetResponse":
        """Add a link widget."""
        self.widgets.append(Widget.link(label, url, icon))
        return self

    def add_app_launch(
        self,
        label: str,
        app_name: Optional[str] = None,
        icon: str = "app.fill"
    ) -> "WidgetResponse":
        """Add an app launch widget."""
        self.widgets.append(Widget.app_launch(label, app_name=app_name, icon=icon))
        return self

    def add_code_block(
        self,
        code: str,
        language: str = "plaintext"
    ) -> "WidgetResponse":
        """Add a code block widget."""
        self.widgets.append(Widget.code_block(code, language))
        return self

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization."""
        result = {
            "text": self.text,
            "images": self.images
        }
        if self.widgets:
            result["widgets"] = widgets_to_list(self.widgets)
        return result
