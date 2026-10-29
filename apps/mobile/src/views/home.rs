use beamlet_ui::Hero;
use dioxus::prelude::*;

#[component]
pub fn Home() -> Element {
    rsx! {
        Hero {}

    }
}
