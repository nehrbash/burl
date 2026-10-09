import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { runInNewContext } from "node:vm";

const read = path => readFileSync(new URL(`../${path}`, import.meta.url), "utf8");
const registry = read("modules/nexus/PageRegistry.qml");
const pageList = registry.match(/readonly property list<var> pages: (\[[\s\S]*?\n    \])/)[1];
const pageComponents = [...registry.matchAll(/readonly property Component (\w+):/g)].map(match => match[1]);
const components = Object.fromEntries(pageComponents.map(name => [name, { name }]));
const pages = runInNewContext(pageList, { root: components, qsTr: text => text });

function harness() {
    const Component = { Ready: 1, Loading: 2, Error: 3 };
    const pending = [];
    const root = { currentItem: null, requestGeneration: 0, disposing: false };
    const container = {};
    const nState = {};
    const context = {
        root, container, nState, Component,
        console: { warn() {} },
        PageRegistry: { page(id) { return { component: {
            incubateObject(parent, props) {
                assert.equal(parent, container);
                assert.equal(props.nState, nState);
                const incubator = {
                    status: Component.Loading,
                    object: { id, ...props, anchors: {}, destroyed: false, destroy() { this.destroyed = true; } },
                    finish(status = Component.Ready) { this.status = status; this.onStatusChanged(status); },
                };
                pending.push(incubator);
                return incubator;
            },
        } }; } },
    };
    for (const key of ["currentItem", "requestGeneration"]) {
        Object.defineProperty(context, key, { get: () => root[key], set: value => { root[key] = value; } });
    }
    const match = read("modules/nexus/Pages.qml").match(/function loadPage\(id: string\): void \{([\s\S]*?)\n    \}/);
    const load = runInNewContext(`(function(id) {${match[1]}})`, context);
    return { root, container, pending, load, Component };
}

test("navigation metadata resolves every visible page to its own component", () => {
    assert.equal(new Set(pages.map(page => page.id)).size, pages.length);
    assert.equal(pages.some(page => page.id === "plugins"), false);
    for (const page of pages) assert.equal(page.component.name, `${page.id}Page`);
    for (const id of ["appearance", "network", "bluetooth", "audio"]) {
        assert.equal(pages.find(page => page.id === id).component.name, `${id}Page`);
    }
    const wrapper = read("modules/bar/popouts/Wrapper.qml");
    assert.match(wrapper, /nState.currentPageId: PageRegistry.page\(root.queuedMode\).id/);
});

test("out-of-order incubation cannot replace the newest selected page", () => {
    const h = harness();
    h.load("network");
    h.load("audio");
    h.pending[1].finish();
    h.pending[0].finish();
    assert.equal(h.root.currentItem.id, "audio");
    assert.equal(h.root.currentItem.visible, true);
    assert.equal(h.root.currentItem.anchors.fill, h.container);
    assert.equal(h.pending[0].object.destroyed, true);
    assert.equal(h.pending[0].object.visible, false);
});

test("selection invalidates pending pages during the exit animation", () => {
    const h = harness();
    h.load("network");
    h.root.requestGeneration++;
    h.pending[0].finish();
    assert.equal(h.root.currentItem, null);
    assert.equal(h.pending[0].object.destroyed, true);
});

test("replacing a ready page releases it, and failed loads remain empty", () => {
    const h = harness();
    h.load("display");
    h.pending[0].finish();
    h.load("network");
    assert.equal(h.pending[0].object.destroyed, true);
    assert.equal(h.root.currentItem, null);
    h.pending[1].finish(h.Component.Error);
    assert.equal(h.root.currentItem, null);
});

test("a page completing during container disposal is destroyed", () => {
    const h = harness();
    h.load("network");
    h.root.disposing = true;
    h.pending[0].finish();
    assert.equal(h.pending[0].object.destroyed, true);
    assert.equal(h.root.currentItem, null);
});
