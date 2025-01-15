import reflex as rx
from ..state import State, BioAllowableActionTypes
from typing import Any, Callable, List

def create_label(text: str) -> rx.Component:
    """Create a label with specific styling."""
    return rx.text(
        text,
        font_weight="500",
        font_size="0.875rem",
        color="var(--text-color)",
        margin_bottom="0.5rem",
    )

def create_button(text, on_click, color_scheme="primary"):
    """Create a button with specific styling."""
    return rx.button(
        text,
        on_click=on_click,
        padding="0.5rem",
        border_radius="md",
        color="var(--text-color)",
        background_color="var(--button-bg)",
        _hover={
            "background_color": "var(--button-hover-bg)",
            "transform": "translateY(-1px)",
        },
        transition="all 0.2s",
    )

def create_input_field(placeholder: str, value: Any, on_change: Any, **kwargs) -> rx.Component:
    """Create a styled input field."""
    return rx.input(
        placeholder=placeholder,
        value=value,
        on_change=on_change,
        border_color="var(--border-color)",
        background_color="var(--input-bg)",
        color="var(--text-color)",
        _hover={"border_color": "var(--border-hover-color)"},
        _focus={"border_color": "var(--border-focus-color)"},
        **kwargs,
    )

def create_textarea(placeholder, value, on_change):
    """Create a textarea element with specified attributes and styling."""
    return rx.text_area(
        placeholder=placeholder,
        value=value,
        on_change=on_change,
        display="block",
        border_color="var(--border-color)",
        background_color="var(--input-bg)",
        color="var(--text-color)",
        _hover={"border_color": "var(--border-hover-color)"},
        _focus={"border_color": "var(--border-focus-color)"},
        margin_top="0.25rem",
        border_radius="0.375rem",
        box_shadow="0 1px 2px 0 rgba(0, 0, 0, 0.05)",
        width="100%",
        min_height="100px",
    )

def create_labeled_input(label_text: str, placeholder: str, value: str, on_change: Callable) -> rx.Component:
    """Create a box containing a label and an input field in a row."""
    return rx.hstack(
        rx.text(label_text, font_weight="500", min_width="150px"),
        rx.input(
            placeholder=placeholder,
            value=value,
            on_change=on_change,
            flex="1",
        ),
        width="100%",
        spacing="4",
    )

def create_labeled_textarea(label_text: str, placeholder: str, value: str, on_change: Callable) -> rx.Component:
    """Create a box containing a label and a textarea in a row."""
    return rx.hstack(
        rx.text(label_text, font_weight="500", min_width="150px"),
        rx.text_area(
            placeholder=placeholder,
            value=value,
            on_change=on_change,
            flex="1",
            min_height="100px",
        ),
        width="100%",
        spacing="4",
        align_items="flex-start",
    )

def create_error_message(error_text: str) -> rx.Component:
    """Create an error message component."""
    return rx.cond(
        error_text != "",
        rx.box(
            rx.text(
                error_text,
                color="red.500",
                font_size="0.875rem",
            ),
            padding="0.5rem",
            border="1px solid",
            border_color="red.200",
            border_radius="md",
            background_color="red.50",
            margin_top="0.5rem",
        ),
    )

def create_success_message(success_text: str) -> rx.Component:
    """Create a success message component."""
    return rx.cond(
        success_text != "",
        rx.box(
            rx.text(
                success_text,
                color="green.500",
                font_size="0.875rem",
            ),
            padding="0.5rem",
            border="1px solid",
            border_color="green.200",
            border_radius="md",
            background_color="green.50",
            margin_top="0.5rem",
        ),
    )

def create_video_player():
    """Create the video player component."""
    return rx.vstack(
        rx.video(
            url=State.video_url,
            width="100%",
            max_width="800px",
            controls=True,
            on_progress=State.update_progress,
        ),
        create_error_message(State.video_error),
        rx.hstack(
            rx.text(f"Current Frame: {State.current_frame} (at {State.current_time:.2f} seconds)", color="var(--text-color)"),
            rx.hstack(
                rx.text("FPS:", font_weight="500", margin_right="0.5rem", color="var(--text-color)"),
                rx.input(
                    placeholder="FPS",
                    value=State.fps,
                    on_change=State.set_fps,
                    min_=1,
                    max_=120,
                    width="100px",
                    border_color="var(--border-color)",
                    background_color="var(--input-bg)",
                    color="var(--text-color)",
                    _hover={"border_color": "var(--border-hover-color)"},
                    _focus={"border_color": "var(--border-focus-color)"},
                ),
            ),
            width="100%",
            justify="between",
            padding="0.5rem",
        ),
        width="100%",
        spacing="4",
    )

def create_annotations_table():
    """Create a table to display annotations."""
    return rx.box(
        rx.heading("Annotations", size="3", margin_bottom="1rem", color="var(--text-color)"),
        rx.data_table(
            data=State.table_data,
            columns=State.table_columns,
            width="100%",
            search=True,
            sort=True,
            pagination=True,
        ),
        rx.hstack(
            rx.spacer(),
            rx.button(
                "Remove Last Annotation",
                on_click=State.remove_last_annotation,
                color_scheme="red",
                size="2",
                margin_top="1rem",
            ),
            width="100%",
        ),
        margin_top="1rem",
        margin_bottom="1rem",
    )

def create_annotation_form():
    """Create the annotation form."""
    return rx.box(
        rx.vstack(
            rx.hstack(
                rx.heading("Annotation Form", size="3"),
                rx.spacer(),
                rx.text(
                    "Structured Mode",
                    margin_left="0.5rem",
                ),
                rx.switch(
                    is_checked=State.is_natural_language_mode,
                    on_change=State.toggle_form_mode,
                ),
                rx.text("Natural Language Mode", color="var(--text-color)"),
                width="100%",
                spacing="4",
            ),
            rx.cond(
                State.is_natural_language_mode,
                create_labeled_textarea(
                    "Description",
                    "Enter natural language description...",
                    State.natural_language_description,
                    State.set_natural_language_description,
                ),
                rx.vstack(
                    rx.select(
                        BioAllowableActionTypes._member_names_,
                        placeholder="Select action type",
                        value=State.action_type,
                        on_change=State.set_action_type,
                        color_scheme="blue",
                    ),
                    create_labeled_input(
                        "Description",
                        "Enter action description",
                        State.action_description,
                        State.set_action_description,
                    ),
                    create_labeled_input(
                        "Apparatus",
                        "Enter detected apparatus (comma-separated)",
                        State.detected_apparatus,
                        State.set_detected_apparatus,
                    ),
                    create_labeled_input(
                        "Instruments",
                        "Enter detected instruments (comma-separated)",
                        State.detected_instruments,
                        State.set_detected_instruments,
                    ),
                    create_labeled_input(
                        "Materials",
                        "Enter detected materials (comma-separated)",
                        State.detected_materials,
                        State.set_detected_materials,
                    ),
                    create_labeled_textarea(
                        "Spatial Info",
                        "Enter spatial information as JSON",
                        State.spatial_information,
                        State.set_spatial_information,
                    ),
                    width="100%",
                    spacing="4",
                ),
            ),
            rx.grid(
                create_button(
                    "Add Annotation",
                    State.add_annotations,
                    color_scheme="green",
                ),
                create_button(
                    "Clear Form",
                    State.clear_form,
                    color_scheme="red",
                ),
                columns="2",
                spacing="4",
                width="100%",
                margin_top="1rem",
            ),
            width="100%",
            spacing="4",
            align_items="stretch",
        ),
        padding="1rem",
        border="1px solid var(--border-color)",
        border_radius="md",
        background="var(--card-bg)",
        width="100%",
        max_width="100%",
    )

def create_huggingface_section():
    """Create the Hugging Face dataset section."""
    return rx.box(
        rx.heading("Hugging Face Dataset", size="3", margin_bottom="1rem", color="var(--text-color)"),
        rx.vstack(
            rx.hstack(
                rx.input(
                    placeholder="username/dataset-name",
                    value=State.hf_dataset_repo,
                    on_change=State.set_hf_dataset_repo,
                    flex="1",
                ),
                rx.switch(
                    is_checked=State.is_private_dataset,
                    on_change=State.set_dataset_privacy,
                ),
                rx.text("Private", margin_left="0.5rem", color="var(--text-color)"),
                width="100%",
                spacing="4",
            ),
            create_button(
                "Push to Hugging Face",
                State.push_to_huggingface,
                color_scheme="green",
            ),
            # Progress section
            rx.cond(
                State.hf_progress != "",
                rx.box(
                    rx.text(
                        State.hf_progress,
                        color="blue.500",
                        font_size="0.875rem",
                    ),
                    padding="0.5rem",
                    border="1px solid",
                    border_color="blue.200",
                    border_radius="md",
                    background_color="blue.50",
                    margin_top="0.5rem",
                ),
            ),
            # Error message
            create_error_message(State.hf_error),
            # Success message
            create_success_message(State.hf_success),
            spacing="4",
            align_items="flex-start",
            width="100%",
        ),
        margin_top="1rem",
        margin_bottom="1rem",
        padding="1rem",
        border="1px solid var(--border-color)",
        border_radius="md",
        background="var(--card-bg)",
        width="100%",
    )

def create_main_content():
    """Create the main content of the page."""
    return rx.box(
        rx.heading("LabAR Video Report Annotation", size="2", margin_bottom="1.5rem", color="var(--text-color)"),
        rx.vstack(
            create_input_field(
                placeholder="Enter video URL...",
                value=State.video_url,
                on_change=State.set_video_url,
                width="100%",
                margin_bottom="1rem",
            ),
            rx.cond(
                State.video_url != "",
                rx.vstack(
                    create_video_player(),
                    rx.divider(margin="2rem 0", border_color="var(--border-color)"),
                    create_annotation_form(),
                    create_annotations_table(),
                    create_huggingface_section(),
                    spacing="4",
                ),
            ),
            width="100%",
            spacing="4",
        ),
        background_color="var(--card-bg)",
        padding="2rem",
        border_radius="lg",
        box_shadow="0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06)",
        max_width="56rem",
        margin="2rem auto",
    )

def index():
    """The main page."""
    return rx.box(
        rx.button(
            rx.icon("moon"),
            on_click=rx.toggle_color_mode,
            float="right",
            background="transparent",
            _hover={"background": "var(--button-hover-bg)"},
        ),
        create_main_content(),
        padding="2rem",
        min_height="100vh",
        background="var(--main-bg)",
        color_scheme="auto",
        style={
            "--main-bg": "hsl(0, 0%, 98%)",
            "--card-bg": "hsl(0, 0%, 100%)",
            "--text-color": "hsl(0, 0%, 20%)",
            "--border-color": "hsl(0, 0%, 85%)",
            "--border-hover-color": "hsl(0, 0%, 70%)",
            "--border-focus-color": "hsl(215, 100%, 50%)",
            "--button-bg": "hsl(215, 100%, 50%)",
            "--button-hover-bg": "hsl(215, 100%, 45%)",
            "--input-bg": "hsl(0, 0%, 100%)",
            "@media (prefers-color-scheme: dark)": {
                "--main-bg": "hsl(0, 0%, 10%)",
                "--card-bg": "hsl(0, 0%, 15%)",
                "--text-color": "hsl(0, 0%, 90%)",
                "--border-color": "hsl(0, 0%, 30%)",
                "--border-hover-color": "hsl(0, 0%, 40%)",
                "--border-focus-color": "hsl(215, 100%, 60%)",
                "--button-bg": "hsl(215, 100%, 50%)",
                "--button-hover-bg": "hsl(215, 100%, 55%)",
                "--input-bg": "hsl(0, 0%, 20%)",
            }
        },
    )