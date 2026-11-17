import json

from conftest import auth
from project.database import add_missing_columns, engine
from sqlalchemy import text
from test_features import tiny_png


def test_tea_defaults_and_custom_ingredients(client, admin_token):
    menu = client.get('/cafeterias/1/menu').json()
    tea = next(item for item in menu if item['name'] == 'شاي مهيل')
    assert tea['removable_ingredients'] == ['سكر']
    assert 'سكر' in tea['ingredients'] and 'بصل' not in tea['ingredients']
    response = client.post('/admin/menu', headers=auth(admin_token), json={
        'name': 'طبق خاص', 'price': 3000, 'ingredients': [' خبز ', 'بصل', 'صوص', 'بصل'],
        'removable_ingredients': ['بصل', 'صوص'],
    })
    assert response.status_code == 201, response.text
    item = response.json()
    assert item['ingredients'] == ['خبز', 'بصل', 'صوص']
    changed = client.patch(f"/admin/menu/{item['id']}", headers=auth(admin_token),
                           json={'name': 'اسم مختلف', 'ingredients': ['خبز', 'صوص']})
    assert changed.status_code == 200
    assert changed.json()['removable_ingredients'] == ['صوص']
    public = client.get('/cafeterias/1/menu').json()
    assert next(v for v in public if v['id'] == item['id'])['ingredients'] == ['خبز', 'صوص']


def test_invalid_removal_is_rejected_without_changes(client, admin_token):
    tea = next(v for v in client.get('/cafeterias/1/menu').json() if v['name'] == 'شاي مهيل')
    for changes in ({'removable_ingredients': ['بصل']}, {'ingredients': None},
                    {'ingredients': ['x' * 41]}, {'ingredients': [str(i) for i in range(21)]}):
        response = client.patch(f"/admin/menu/{tea['id']}", headers=auth(admin_token), json=changes)
        assert response.status_code == 422, response.text
    assert next(v for v in client.get('/cafeterias/1/menu').json() if v['id'] == tea['id']) == tea


def test_photo_and_ingredients_saved_together(client, admin_token):
    fields = {'name': 'شاي جديد', 'price': '500',
              'ingredients': json.dumps(['شاي', 'ماء', 'سكر']),
              'removable_ingredients': json.dumps(['سكر'])}
    response = client.post('/admin/menu/with-image', headers=auth(admin_token), data=fields,
                           files={'file': ('tea.png', tiny_png(), 'image/png')})
    assert response.status_code == 201, response.text
    assert response.json()['removable_ingredients'] == ['سكر']
    assert client.get(response.json()['image_url']).content == tiny_png()
    before = client.get('/cafeterias/1/menu').json()
    for invalid in ('not-json', json.dumps(['بصل'])):
        fields['removable_ingredients'] = invalid
        response = client.post('/admin/menu/with-image', headers=auth(admin_token), data=fields,
                               files={'file': ('tea.png', tiny_png(), 'image/png')})
        assert response.status_code == 422
    assert client.get('/cafeterias/1/menu').json() == before


def test_legacy_menu_migrates_once_without_losing_owner_edits(client, admin_token):
    with engine.begin() as conn:
        conn.execute(text('ALTER TABLE menu_items DROP COLUMN ingredients'))
        conn.execute(text('ALTER TABLE menu_items DROP COLUMN removable_ingredients'))
        conn.execute(text('DELETE FROM schema_migrations WHERE version = 4'))
    add_missing_columns()
    tea = next(v for v in client.get('/cafeterias/1/menu').json() if v['name'] == 'شاي مهيل')
    assert tea['removable_ingredients'] == ['سكر']
    response = client.patch(f"/admin/menu/{tea['id']}", headers=auth(admin_token),
                            json={'ingredients': ['شاي', 'ماء'], 'removable_ingredients': []})
    assert response.status_code == 200
    add_missing_columns()
    tea = next(v for v in client.get('/cafeterias/1/menu').json() if v['name'] == 'شاي مهيل')
    assert tea['ingredients'] == ['شاي', 'ماء'] and tea['removable_ingredients'] == []
