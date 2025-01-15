from typing import List, Dict, Any, Optional, Tuple
import os
import json
from datetime import datetime
from langchain.output_parsers import PydanticOutputParser
from langchain.prompts import PromptTemplate
from langchain_openai import ChatOpenAI

import reflex as rx
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

from huggingface_hub import HfApi, CommitOperationAdd
from huggingface_hub.utils import RepositoryNotFoundError
import tempfile

# Import from app/models
import sys
from _PATH import EXTRA_PATHS
sys.path.extend(EXTRA_PATHS)
from models.llm.action_steps import ImageActionFrame, BioAllowableActionTypes

class State(rx.State):
    """The app state."""
    # Video state
    video_url: str = ""
    video_error: str = ""
    current_time: float = 0
    fps: int = 60  # default fps

    def validate_video_url(self, url: str) -> bool:
        """Validate video URL format and accessibility."""
        try:
            if not url:
                self.video_error = "Please enter a video URL"
                return False
                
            # Check URL format
            from urllib.parse import urlparse
            result = urlparse(url)
            if not all([result.scheme, result.netloc]):
                self.video_error = "Invalid URL format"
                return False
            
            # Check if URL ends with common video extensions
            video_extensions = ['.mp4', '.webm', '.ogg', '.mov']
            if not any(url.lower().endswith(ext) for ext in video_extensions):
                self.video_error = "URL must point to a video file (mp4, webm, ogg, mov)"
                return False
            
            # TODO: Add actual video file accessibility check if needed
            return True
            
        except Exception as e:
            self.video_error = f"Error validating URL: {str(e)}"
            return False
    
    def set_video_url(self, url: str):
        """Set the video URL with validation."""
        self.video_error = ""  # Clear previous errors
        if self.validate_video_url(url):
            self.video_url = url
        else:
            self.video_url = ""  # Clear invalid URL
    
    def update_progress(self, progress: dict):
        """Update the current time from progress data."""
        try:
            self.current_time = progress["playedSeconds"]
        except (KeyError, TypeError) as e:
            self.video_error = f"Error updating video progress: {str(e)}"
    
    def set_fps(self, value: str):
        """Set the FPS value with validation."""
        try:
            fps = int(value)
            if fps <= 0:
                self.video_error = "FPS must be greater than 0"
            else:
                self.fps = fps
                self.video_error = ""
        except ValueError:
            self.video_error = "FPS must be a valid number"

    @rx.var
    def current_frame(self) -> int:
        """Calculate current frame from time."""
        return int(self.current_time * self.fps)