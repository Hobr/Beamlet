use dioxus::prelude::*;
use beamlet_ui::Hero;

#[component]
pub fn Home() -> Element {
    rsx! {
        Hero {}

    }
}
