import pytest
from conftest import auth
from project.manage import create_platform_admin


@pytest.fixture
def platform_token(client):
    create_platform_admin('admin', 'platform-secret-123')
    response = client.post('/platform/login', json={'username': 'ADMIN', 'password': 'platform-secret-123'})
    assert response.status_code == 200
    return response.json()['token']


def cafeteria_payload(**changes):
    return {'name': 'كافيتريا الهندسة', 'location': 'بناية الهندسة',
            'open_hour': 8, 'close_hour': 17, 'code': 'Engineering-2026!', **changes}


def test_only_platform_admin_can_add_cafeterias(client, platform_token, student_token, admin_token):
    for token, status in [(None, 401), (student_token, 403), (admin_token, 403)]:
        response = client.post('/platform/cafeterias', headers=auth(token) if token else {}, json=cafeteria_payload())
        assert response.status_code == status
    response = client.post('/platform/cafeterias', headers=auth(platform_token), json=cafeteria_payload())
    assert response.status_code == 201, response.text
    cafe = response.json()
    assert 'code' not in cafe and 'code_hash' not in cafe
    assert any(c['id'] == cafe['id'] for c in client.get('/cafeterias').json())
    assert any(c['id'] == cafe['id'] for c in client.get('/platform/cafeterias', headers=auth(platform_token)).json())
    owner = client.post('/admin/login', json={'cafeteria_id': cafe['id'], 'code': 'Engineering-2026!'})
    assert owner.status_code == 200
    assert client.get('/admin/orders', headers=auth(platform_token)).status_code == 403
    assert client.patch('/admin/menu/1', headers=auth(owner.json()['token']), json={'price': 1}).status_code == 404
    assert client.post('/platform/cafeterias', headers=auth(platform_token), json=cafeteria_payload()).status_code == 409


@pytest.mark.parametrize('change', [
    {'name': '  '}, {'location': '  '}, {'open_hour': -1}, {'open_hour': 24},
    {'close_hour': 25}, {'close_hour': 8}, {'code': 'short'}, {'code': 'رمز-كافيتريا-طويل'}, {'code': 'space inside code'},
])
def test_invalid_cafeteria_is_not_created(client, platform_token, change):
    before = client.get('/cafeterias').json()
    response = client.post('/platform/cafeterias', headers=auth(platform_token), json=cafeteria_payload(**change))
    assert response.status_code == 422, response.text
    assert client.get('/cafeterias').json() == before


def test_platform_password_change_revokes_old_token(client, platform_token):
    response = client.post('/platform/password', headers=auth(platform_token),
                           json={'current_password': 'platform-secret-123', 'new_password': 'new-platform-secret-456'})
    assert response.status_code == 200
    assert client.get('/platform/me', headers=auth(platform_token)).status_code == 401
    assert client.get('/platform/me', headers=auth(response.json()['token'])).status_code == 200
    assert client.post('/platform/login', json={'username': 'admin', 'password': 'platform-secret-123'}).status_code == 401
    assert client.post('/platform/login', json={'username': 'admin', 'password': 'new-platform-secret-456'}).status_code == 200


def test_no_automatic_admin_and_no_silent_overwrite(client):
    assert client.post('/platform/login', json={'username': 'admin', 'password': 'admin'}).status_code == 401
    create_platform_admin('admin', 'platform-secret-123')
    with pytest.raises(ValueError, match='already exists'):
        create_platform_admin('admin', 'replacement-secret-123')
    assert client.post('/platform/login', json={'username': 'admin', 'password': 'platform-secret-123'}).status_code == 200
