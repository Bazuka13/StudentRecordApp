# Local and CI test suite for Student ERP Application
import os
import sys

# Ensure webapp directory is in path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

os.environ["TABLE_NAME"] = "StudentRecords"
os.environ["AWS_REGION"] = "us-east-1"
os.environ["AWS_ACCESS_KEY_ID"] = "testing"
os.environ["AWS_SECRET_ACCESS_KEY"] = "testing"

def run_tests():
    import app as webapp
    c = webapp.app.test_client()

    # 1. Health check
    health_res = c.get("/health")
    assert health_res.status_code == 200, f"Expected 200, got {health_res.status_code}"
    health_data = health_res.get_json()
    assert health_data["status"] == "ok"
    print("[PASS] /health passed:", health_data)

    # 2. Add student POST
    r = c.post("/add", data={"name": "Samarth", "course": "Cloud Computing", "email": "s@example.com"})
    assert r.status_code == 302, f"Expected 302, got {r.status_code}"
    print("[PASS] /add student passed with 302 redirect")

    # 3. View Index HTML
    html = c.get("/").get_data(as_text=True)
    assert "Samarth" in html and "Cloud Computing" in html, "Expected 'Samarth' and 'Cloud Computing' in HTML"
    print("[PASS] / contains Samarth and Cloud Computing")

    # 4. Test Student Portal view
    student_res = c.get("/?view=student")
    assert student_res.status_code == 200
    student_html = student_res.get_data(as_text=True)
    assert "Attendance" in student_html or "CGPA" in student_html
    print("[PASS] Student portal view verified")

    # 5. Test Export API
    export_res = c.get("/export/csv")
    assert export_res.status_code == 200
    assert "text/csv" in export_res.headers.get("Content-Type", "")
    print("[PASS] Export CSV verified")

    # 6. Test JSON API
    api_res = c.get("/api/students")
    assert api_res.status_code == 200
    assert len(api_res.get_json()["students"]) > 0
    print("[PASS] REST API verified")

    print("\n==========================================")
    print("ALL TESTS PASSED SUCCESSFULLY!")
    print("==========================================")

if __name__ == "__main__":
    try:
        from moto import mock_aws
        import boto3
        with mock_aws():
            ddb = boto3.resource("dynamodb", region_name="us-east-1")
            ddb.create_table(
                TableName="StudentRecords",
                KeySchema=[{"AttributeName": "studentId", "KeyType": "HASH"}],
                AttributeDefinitions=[{"AttributeName": "studentId", "AttributeType": "S"}],
                BillingMode="PAY_PER_REQUEST",
            )
            run_tests()
    except ImportError:
        print("[NOTE] moto is not installed, running with built-in storage manager...")
        run_tests()
