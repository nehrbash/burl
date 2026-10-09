import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import { test } from 'node:test';

const source = readFileSync(new URL('../services/Weather.qml', import.meta.url), 'utf8');
function weather() {
    const requests = [];
    const state = {
        locationRequest: 0, requestedLocation: '', locating: false, locationError: '',
        loc: '', city: '', cc: null, forecast: [], hourlyForecast: [], cachedCities: new Map(),
        GlobalConfig: {services: {weatherLocation: ''}},
        Requests: {get: (url, success, failure) => requests.push({url, success, failure})},
        timer: {elapsed: () => 0, restart() {}},
        Qt: {locale: () => ({name: 'en_US'})}, qsTr: text => text,
    };
    state.root = state;
    for (const match of source.matchAll(/^    function (\w+)\((.*?)\): \w+ \{([\s\S]*?)^    \}/gm)) {
        const params = match[2].replace(/: \w+/g, '');
        state[match[1]] = runInNewContext(`(function(${params}) {${match[3]}})`, state);
    }
    return {state, requests};
}

test('invalid city stops after one lookup and a subsequent valid city resolves', () => {
    const {state, requests} = weather();
    state.GlobalConfig.services.weatherLocation = 'nonexistent';
    state.reload();
    requests[0].success('{"results":[]}');
    assert.equal(requests.length, 1);
    assert.equal(state.locating, false);
    assert.match(state.locationError, /not found/);
    state.GlobalConfig.services.weatherLocation = 'Boston';
    state.reload(true);
    requests[1].success(JSON.stringify({results: [{latitude: 42.36, longitude: -71.06, name: 'Boston'}]}));
    assert.equal(state.loc, '42.36,-71.06');
    assert.equal(state.city, 'Boston');
    assert.equal(state.locationError, '');
});

test('clearing explicit location detects automatically even with a fresh cache', () => {
    const {state, requests} = weather();
    state.requestedLocation = 'Boston';
    state.loc = '42.36,-71.06';
    state.cc = {tempC: 12};
    state.reload(true);
    assert.equal(state.loc, '');
    assert.equal(state.cc, null);
    assert.match(requests[0].url, /ipinfo/);
    requests[0].success('{"loc":"48.85,2.35","city":"Paris"}');
    assert.equal(state.city, 'Paris');
    assert.equal(state.loc, '48.85,2.35');
});

test('old lookup responses and failures cannot replace the current selection', () => {
    const {state, requests} = weather();
    state.GlobalConfig.services.weatherLocation = 'Boston';
    state.reload();
    state.GlobalConfig.services.weatherLocation = 'Paris';
    state.reload(true);
    requests[1].success('{"results":[{"latitude":48.85,"longitude":2.35,"name":"Paris"}]}');
    requests[0].success('{"results":[{"latitude":42.36,"longitude":-71.06,"name":"Boston"}]}');
    requests[0].failure();
    assert.equal(state.city, 'Paris');
    assert.equal(state.locationError, '');
});

test('bad coordinates fail locally and network errors allow an explicit retry', () => {
    const {state, requests} = weather();
    for (const value of ['91,0', '0,181', '42,garbage']) {
        state.GlobalConfig.services.weatherLocation = value;
        state.reload(true);
        assert.equal(requests.length, 0);
        assert.equal(state.locating, false);
        assert.match(state.locationError, /latitude/);
    }
    state.GlobalConfig.services.weatherLocation = '';
    state.reload(true);
    requests[0].failure();
    assert.match(state.locationError, /connection/);
    state.reload(true);
    assert.equal(requests.length, 2);
});

test('weather response from an old location is ignored', () => {
    const {state, requests} = weather();
    state.loc = '42,-71';
    state.fetchWeatherData();
    state.loc = '48,2';
    requests[0].success('{"current":{},"daily":{}}');
    assert.equal(state.cc, null);
});
