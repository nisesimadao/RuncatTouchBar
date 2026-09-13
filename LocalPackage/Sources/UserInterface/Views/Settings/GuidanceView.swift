/*
 GuidanceView.swift
 UserInterface

 Created by Takuto Nakamura on 2026/08/06.
 Copyright 2026 Kyome22 (Takuto Nakamura)

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

import SwiftUI

struct GuidanceView: View {
    var description: LocalizedStringKey
    var linkLabel: LocalizedStringKey
    var linkDestination: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(description, bundle: .module)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Link(destination: linkDestination) {
                Text(linkLabel, bundle: .module)
                    .font(.caption)
            }
        }
        .padding()
        .frame(maxWidth: 360, alignment: .leading)
    }
}
