import os
import json
import sqlite3
import uuid
import datetime
from decimal import Decimal
import boto3
from botocore.exceptions import BotoCoreError, ClientError

TABLE_NAME = os.environ.get("TABLE_NAME", "StudentRecords")
AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")
DB_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "students.db")

# Sample courses catalog
CATALOG_COURSES = [
    {
        "code": "CS-401",
        "name": "Cloud Computing & Distributed Systems",
        "credits": 4,
        "department": "Computer Science & Engineering",
        "instructor": "Prof. Alan Vance",
        "schedule": "Mon, Wed 10:00 - 11:30 AM",
        "room": "Hall 302",
        "capacity": 60,
        "enrolledCount": 48,
    },
    {
        "code": "CS-405",
        "name": "Deep Learning & Neural Networks",
        "credits": 4,
        "department": "AI & Machine Learning",
        "instructor": "Dr. Anita Rao",
        "schedule": "Tue, Thu 02:00 - 03:30 PM",
        "room": "AI Lab 4",
        "capacity": 50,
        "enrolledCount": 42,
    },
    {
        "code": "CS-412",
        "name": "Modern Web Architectures & APIs",
        "credits": 3,
        "department": "Computer Science & Engineering",
        "instructor": "Prof. David Kim",
        "schedule": "Mon, Wed 02:00 - 03:15 PM",
        "room": "Room 204",
        "capacity": 55,
        "enrolledCount": 51,
    },
    {
        "code": "CS-308",
        "name": "Database Systems & Scalable Storage",
        "credits": 4,
        "department": "Computer Science & Engineering",
        "instructor": "Dr. Elena Thorne",
        "schedule": "Tue, Thu 10:00 - 11:30 AM",
        "room": "Room 108",
        "capacity": 60,
        "enrolledCount": 56,
    },
    {
        "code": "MA-302",
        "name": "Applied Probability & Statistics",
        "credits": 3,
        "department": "Mathematics & Computing",
        "instructor": "Prof. Robert Miller",
        "schedule": "Fri 09:00 - 11:30 AM",
        "room": "Lecture Hall B",
        "capacity": 70,
        "enrolledCount": 65,
    },
    {
        "code": "EN-201",
        "name": "Technical Communication & Ethics",
        "credits": 2,
        "department": "Humanities",
        "instructor": "Prof. Clara Oswald",
        "schedule": "Fri 02:00 - 04:00 PM",
        "room": "Seminar Hall 1",
        "capacity": 80,
        "enrolledCount": 74,
    },
    {
        "code": "CS-480",
        "name": "Cyber Security & Ethical Hacking",
        "credits": 3,
        "department": "Information Security",
        "instructor": "Prof. Marcus Finch",
        "schedule": "Wed, Fri 04:00 - 05:30 PM",
        "room": "Security Lab 2",
        "capacity": 45,
        "enrolledCount": 38,
    },
    {
        "code": "DS-420",
        "name": "Big Data Analytics with Apache Spark",
        "credits": 3,
        "department": "Data Science",
        "instructor": "Dr. Liam Smith",
        "schedule": "Thu 04:00 - 06:30 PM",
        "room": "Data Center Lab",
        "capacity": 40,
        "enrolledCount": 35,
    },
]

CATALOG_NOTICES = [
    {
        "id": "NOT-001",
        "title": "Fall Semester Final Examination Schedule Published",
        "category": "Exam",
        "priority": "Urgent",
        "date": "Today",
        "author": "Controller of Examinations",
        "content": "The comprehensive exam timetable for Fall 2026 has been published. All students must download their digital hall tickets and verify course codes by Nov 10.",
    },
    {
        "id": "NOT-002",
        "title": "Campus Placement Drive: AWS Cloud Architects & SDE Internships",
        "category": "Placement",
        "priority": "High",
        "date": "Yesterday",
        "author": "Career Development Center",
        "content": "Amazon AWS and Microsoft are hosting campus recruitment for 3rd and 4th-year students with CGPA >= 7.5. Submit resumes via the placement portal before Friday.",
    },
    {
        "id": "NOT-003",
        "title": "Semester Tuition & Lab Fee Submission Deadline Notice",
        "category": "Finance",
        "priority": "High",
        "date": "Oct 28",
        "author": "Accounts & Bursar Office",
        "content": "Students with pending dues must clear outstanding semester fees to avoid late charges and course deregistration. Online fee receipt is generated immediately upon payment.",
    },
    {
        "id": "NOT-004",
        "title": "Annual Inter-University Hackathon 'HackNova 2026' Registrations Open",
        "category": "Event",
        "priority": "Normal",
        "date": "Oct 25",
        "author": "Innovation & Student Council",
        "content": "Registrations are open for the 36-hour flagship hackathon with $15,000 in prizes. Team formation and mentorship tracks in AI, Cloud, and Web3.",
    },
    {
        "id": "NOT-005",
        "title": "IEEE Xplore & University Digital Library Remote Access Upgraded",
        "category": "Academic",
        "priority": "Normal",
        "date": "Oct 22",
        "author": "Chief University Librarian",
        "content": "University library has upgraded remote VPN and single-sign-on access for research databases, journals, and ACM digital library.",
    },
]

DEFAULT_TIMETABLE = [
    {"day": "Monday", "time": "10:00 - 11:30 AM", "course": "CS-401 Cloud Computing", "room": "Hall 302", "instructor": "Prof. Alan Vance", "color": "blue"},
    {"day": "Monday", "time": "02:00 - 03:15 PM", "course": "CS-412 Modern Web APIs", "room": "Room 204", "instructor": "Prof. David Kim", "color": "emerald"},
    {"day": "Tuesday", "time": "10:00 - 11:30 AM", "course": "CS-308 Database Systems", "room": "Room 108", "instructor": "Dr. Elena Thorne", "color": "purple"},
    {"day": "Tuesday", "time": "02:00 - 03:30 PM", "course": "CS-405 Deep Learning", "room": "AI Lab 4", "instructor": "Dr. Anita Rao", "color": "amber"},
    {"day": "Wednesday", "time": "10:00 - 11:30 AM", "course": "CS-401 Cloud Computing", "room": "Hall 302", "instructor": "Prof. Alan Vance", "color": "blue"},
    {"day": "Wednesday", "time": "02:00 - 03:15 PM", "course": "CS-412 Modern Web APIs", "room": "Room 204", "instructor": "Prof. David Kim", "color": "emerald"},
    {"day": "Thursday", "time": "10:00 - 11:30 AM", "course": "CS-308 Database Systems", "room": "Room 108", "instructor": "Dr. Elena Thorne", "color": "purple"},
    {"day": "Thursday", "time": "02:00 - 03:30 PM", "course": "CS-405 Deep Learning", "room": "AI Lab 4", "instructor": "Dr. Anita Rao", "color": "amber"},
    {"day": "Friday", "time": "09:00 - 11:30 AM", "course": "MA-302 Applied Probability", "room": "Hall B", "instructor": "Prof. Robert Miller", "color": "rose"},
    {"day": "Friday", "time": "02:00 - 04:00 PM", "course": "EN-201 Technical Ethics", "room": "Seminar 1", "instructor": "Prof. Clara Oswald", "color": "indigo"},
]

SEED_STUDENTS = [
    {
        "studentId": "STU-1001",
        "name": "Samarth Sharma",
        "course": "Cloud Computing",
        "email": "samarth@university.edu",
        "rollNo": "2023CSB1042",
        "department": "Computer Science & Engineering",
        "year": "3rd Year",
        "semester": "Semester 6",
        "phone": "+1 (555) 349-2810",
        "status": "Active",
        "cgpa": 9.24,
        "attendance": 88,
        "feesStatus": "Paid",
        "feesTotal": 4500,
        "feesPaid": 4500,
        "feesDue": 0,
        "advisor": "Dr. Alan Vance",
        "address": "402 North Campus Way, University District",
        "courses": [
            {"code": "CS-401", "name": "Cloud Computing & Distributed Systems", "credits": 4, "instructor": "Prof. Alan Vance", "schedule": "Mon, Wed 10:00 AM", "room": "Hall 302", "attendance": 92, "classesTotal": 24, "classesAttended": 22},
            {"code": "CS-405", "name": "Deep Learning & Neural Networks", "credits": 4, "instructor": "Dr. Anita Rao", "schedule": "Tue, Thu 02:00 PM", "room": "AI Lab 4", "attendance": 88, "classesTotal": 24, "classesAttended": 21},
            {"code": "CS-412", "name": "Modern Web Architectures & APIs", "credits": 3, "instructor": "Prof. David Kim", "schedule": "Mon, Wed 02:00 PM", "room": "Room 204", "attendance": 85, "classesTotal": 20, "classesAttended": 17},
            {"code": "CS-308", "name": "Database Systems & Scalable Storage", "credits": 4, "instructor": "Dr. Elena Thorne", "schedule": "Tue, Thu 10:00 AM", "room": "Room 108", "attendance": 90, "classesTotal": 22, "classesAttended": 20},
            {"code": "MA-302", "name": "Applied Probability & Statistics", "credits": 3, "instructor": "Prof. Robert Miller", "schedule": "Fri 09:00 AM", "room": "Hall B", "attendance": 86, "classesTotal": 14, "classesAttended": 12},
        ],
        "grades": [
            {"code": "CS-401", "name": "Cloud Computing & Distributed Systems", "credits": 4, "grade": "A+", "points": 10.0, "status": "Passed"},
            {"code": "CS-405", "name": "Deep Learning & Neural Networks", "credits": 4, "grade": "A", "points": 9.0, "status": "Passed"},
            {"code": "CS-412", "name": "Modern Web Architectures & APIs", "credits": 3, "grade": "A+", "points": 10.0, "status": "Passed"},
            {"code": "CS-308", "name": "Database Systems & Scalable Storage", "credits": 4, "grade": "A-", "points": 8.7, "status": "Passed"},
            {"code": "MA-302", "name": "Applied Probability & Statistics", "credits": 3, "grade": "A", "points": 9.0, "status": "Passed"},
        ],
        "payments": [
            {"receiptId": "REC-94101", "date": "2026-08-15", "amount": 4500, "method": "Online Banking", "semester": "Fall 2026", "status": "Completed"}
        ]
    },
    {
        "studentId": "STU-1002",
        "name": "Priya Patel",
        "course": "Artificial Intelligence & Data Science",
        "email": "priya.p@university.edu",
        "rollNo": "2024AID2011",
        "department": "AI & Machine Learning",
        "year": "2nd Year",
        "semester": "Semester 4",
        "phone": "+1 (555) 782-9901",
        "status": "Active",
        "cgpa": 8.95,
        "attendance": 94,
        "feesStatus": "Paid",
        "feesTotal": 4500,
        "feesPaid": 4500,
        "feesDue": 0,
        "advisor": "Dr. Anita Rao",
        "address": "128 Oakwood Circle, Apt 4B",
        "courses": [
            {"code": "CS-405", "name": "Deep Learning & Neural Networks", "credits": 4, "instructor": "Dr. Anita Rao", "schedule": "Tue, Thu 02:00 PM", "room": "AI Lab 4", "attendance": 96, "classesTotal": 24, "classesAttended": 23},
            {"code": "DS-420", "name": "Big Data Analytics with Apache Spark", "credits": 3, "instructor": "Dr. Liam Smith", "schedule": "Thu 04:00 PM", "room": "Data Center", "attendance": 92, "classesTotal": 14, "classesAttended": 13},
            {"code": "CS-308", "name": "Database Systems & Scalable Storage", "credits": 4, "instructor": "Dr. Elena Thorne", "schedule": "Tue, Thu 10:00 AM", "room": "Room 108", "attendance": 95, "classesTotal": 22, "classesAttended": 21},
            {"code": "MA-302", "name": "Applied Probability & Statistics", "credits": 3, "instructor": "Prof. Robert Miller", "schedule": "Fri 09:00 AM", "room": "Hall B", "attendance": 93, "classesTotal": 14, "classesAttended": 13},
        ],
        "grades": [
            {"code": "CS-405", "name": "Deep Learning & Neural Networks", "credits": 4, "grade": "A+", "points": 10.0, "status": "Passed"},
            {"code": "DS-420", "name": "Big Data Analytics with Apache Spark", "credits": 3, "grade": "A", "points": 9.0, "status": "Passed"},
            {"code": "CS-308", "name": "Database Systems & Scalable Storage", "credits": 4, "grade": "A", "points": 9.0, "status": "Passed"},
            {"code": "MA-302", "name": "Applied Probability & Statistics", "credits": 3, "grade": "A-", "points": 8.5, "status": "Passed"},
        ],
        "payments": [
            {"receiptId": "REC-93821", "date": "2026-08-14", "amount": 4500, "method": "Credit Card", "semester": "Fall 2026", "status": "Completed"}
        ]
    },
    {
        "studentId": "STU-1003",
        "name": "Alex Rivera",
        "course": "Software Engineering & DevOps",
        "email": "alex.r@university.edu",
        "rollNo": "2023CSB1109",
        "department": "Computer Science & Engineering",
        "year": "3rd Year",
        "semester": "Semester 6",
        "phone": "+1 (555) 431-8842",
        "status": "Active",
        "cgpa": 7.82,
        "attendance": 71,
        "feesStatus": "Partial",
        "feesTotal": 4500,
        "feesPaid": 3000,
        "feesDue": 1500,
        "advisor": "Prof. David Kim",
        "address": "88 Elm Street, Suite 12",
        "courses": [
            {"code": "CS-401", "name": "Cloud Computing & Distributed Systems", "credits": 4, "instructor": "Prof. Alan Vance", "schedule": "Mon, Wed 10:00 AM", "room": "Hall 302", "attendance": 75, "classesTotal": 24, "classesAttended": 18},
            {"code": "CS-412", "name": "Modern Web Architectures & APIs", "credits": 3, "instructor": "Prof. David Kim", "schedule": "Mon, Wed 02:00 PM", "room": "Room 204", "attendance": 70, "classesTotal": 20, "classesAttended": 14},
            {"code": "CS-480", "name": "Cyber Security & Ethical Hacking", "credits": 3, "instructor": "Prof. Marcus Finch", "schedule": "Wed, Fri 04:00 PM", "room": "Sec Lab", "attendance": 68, "classesTotal": 19, "classesAttended": 13},
        ],
        "grades": [
            {"code": "CS-401", "name": "Cloud Computing & Distributed Systems", "credits": 4, "grade": "B+", "points": 8.0, "status": "Passed"},
            {"code": "CS-412", "name": "Modern Web Architectures & APIs", "credits": 3, "grade": "B", "points": 7.5, "status": "Passed"},
            {"code": "CS-480", "name": "Cyber Security & Ethical Hacking", "credits": 3, "grade": "B+", "points": 8.0, "status": "Passed"},
        ],
        "payments": [
            {"receiptId": "REC-92144", "date": "2026-08-20", "amount": 3000, "method": "Debit Card", "semester": "Fall 2026", "status": "Completed"}
        ]
    },
    {
        "studentId": "STU-1004",
        "name": "Marcus Chen",
        "course": "Robotics & Embedded Systems",
        "email": "m.chen@university.edu",
        "rollNo": "2022EEB084",
        "department": "Electrical & Electronics",
        "year": "4th Year",
        "semester": "Semester 8",
        "phone": "+1 (555) 902-1243",
        "status": "Active",
        "cgpa": 9.60,
        "attendance": 91,
        "feesStatus": "Paid",
        "feesTotal": 4800,
        "feesPaid": 4800,
        "feesDue": 0,
        "advisor": "Dr. Harrison Ford",
        "address": "512 Pinecrest Boulevard",
        "courses": [
            {"code": "CS-401", "name": "Cloud Computing & Distributed Systems", "credits": 4, "instructor": "Prof. Alan Vance", "schedule": "Mon, Wed 10:00 AM", "room": "Hall 302", "attendance": 90, "classesTotal": 24, "classesAttended": 21},
            {"code": "CS-308", "name": "Database Systems & Scalable Storage", "credits": 4, "instructor": "Dr. Elena Thorne", "schedule": "Tue, Thu 10:00 AM", "room": "Room 108", "attendance": 92, "classesTotal": 22, "classesAttended": 20},
            {"code": "EN-201", "name": "Technical Communication & Ethics", "credits": 2, "instructor": "Prof. Clara Oswald", "schedule": "Fri 02:00 PM", "room": "Seminar 1", "attendance": 90, "classesTotal": 14, "classesAttended": 13},
        ],
        "grades": [
            {"code": "CS-401", "name": "Cloud Computing & Distributed Systems", "credits": 4, "grade": "O", "points": 10.0, "status": "Passed"},
            {"code": "CS-308", "name": "Database Systems & Scalable Storage", "credits": 4, "grade": "A+", "points": 9.8, "status": "Passed"},
            {"code": "EN-201", "name": "Technical Communication & Ethics", "credits": 2, "grade": "A+", "points": 9.5, "status": "Passed"},
        ],
        "payments": [
            {"receiptId": "REC-91040", "date": "2026-08-10", "amount": 4800, "method": "Bank Transfer", "semester": "Fall 2026", "status": "Completed"}
        ]
    },
    {
        "studentId": "STU-1005",
        "name": "Elena Rostova",
        "course": "Financial Analytics & Management",
        "email": "elena.r@university.edu",
        "rollNo": "2025BBA3019",
        "department": "Business & Management",
        "year": "1st Year",
        "semester": "Semester 2",
        "phone": "+1 (555) 219-5431",
        "status": "Active",
        "cgpa": 8.40,
        "attendance": 82,
        "feesStatus": "Pending",
        "feesTotal": 4200,
        "feesPaid": 1000,
        "feesDue": 3200,
        "advisor": "Dr. Sophia Sterling",
        "address": "19 West End Avenue",
        "courses": [
            {"code": "MA-302", "name": "Applied Probability & Statistics", "credits": 3, "instructor": "Prof. Robert Miller", "schedule": "Fri 09:00 AM", "room": "Hall B", "attendance": 85, "classesTotal": 14, "classesAttended": 12},
            {"code": "EN-201", "name": "Technical Communication & Ethics", "credits": 2, "instructor": "Prof. Clara Oswald", "schedule": "Fri 02:00 PM", "room": "Seminar 1", "attendance": 80, "classesTotal": 14, "classesAttended": 11},
        ],
        "grades": [
            {"code": "MA-302", "name": "Applied Probability & Statistics", "credits": 3, "grade": "A", "points": 8.8, "status": "Passed"},
            {"code": "EN-201", "name": "Technical Communication & Ethics", "credits": 2, "grade": "A-", "points": 8.2, "status": "Passed"},
        ],
        "payments": [
            {"receiptId": "REC-89020", "date": "2026-09-01", "amount": 1000, "method": "Cash Deposit", "semester": "Fall 2026", "status": "Completed"}
        ]
    }
]


class StorageManager:
    def __init__(self):
        self.use_dynamodb = False
        self.dynamodb = None
        self.table = None
        self._init_sqlite()
        self._test_dynamodb()

    def _init_sqlite(self):
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS students (
                studentId TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                course TEXT NOT NULL,
                email TEXT NOT NULL,
                rollNo TEXT,
                department TEXT,
                year TEXT,
                semester TEXT,
                phone TEXT,
                status TEXT DEFAULT 'Active',
                cgpa REAL DEFAULT 8.0,
                attendance REAL DEFAULT 85.0,
                feesStatus TEXT DEFAULT 'Paid',
                feesTotal REAL DEFAULT 4500.0,
                feesPaid REAL DEFAULT 4500.0,
                feesDue REAL DEFAULT 0.0,
                advisor TEXT,
                address TEXT,
                courses_json TEXT,
                grades_json TEXT,
                payments_json TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS notices (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                category TEXT NOT NULL,
                priority TEXT NOT NULL,
                date TEXT NOT NULL,
                author TEXT NOT NULL,
                content TEXT NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        conn.commit()

        # Seed initial records if empty
        cursor.execute("SELECT COUNT(*) FROM students")
        count = cursor.fetchone()[0]
        if count == 0:
            for s in SEED_STUDENTS:
                self._insert_sqlite_student(cursor, s)
            for n in CATALOG_NOTICES:
                cursor.execute("""
                    INSERT INTO notices (id, title, category, priority, date, author, content)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                """, (n["id"], n["title"], n["category"], n["priority"], n["date"], n["author"], n["content"]))
            conn.commit()
        conn.close()

    def _insert_sqlite_student(self, cursor, s):
        cursor.execute("""
            INSERT OR REPLACE INTO students (
                studentId, name, course, email, rollNo, department, year, semester,
                phone, status, cgpa, attendance, feesStatus, feesTotal, feesPaid, feesDue,
                advisor, address, courses_json, grades_json, payments_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            s.get("studentId"),
            s.get("name"),
            s.get("course"),
            s.get("email"),
            s.get("rollNo", "2024REG" + s.get("studentId", "001")[-3:]),
            s.get("department", "Computer Science & Engineering"),
            s.get("year", "3rd Year"),
            s.get("semester", "Semester 6"),
            s.get("phone", "+1 (555) 000-0000"),
            s.get("status", "Active"),
            float(s.get("cgpa", 8.0)),
            float(s.get("attendance", 85.0)),
            s.get("feesStatus", "Paid"),
            float(s.get("feesTotal", 4500.0)),
            float(s.get("feesPaid", 4500.0)),
            float(s.get("feesDue", 0.0)),
            s.get("advisor", "Dr. Alan Vance"),
            s.get("address", "Main Campus, University District"),
            json.dumps(s.get("courses", [])),
            json.dumps(s.get("grades", [])),
            json.dumps(s.get("payments", [])),
        ))

    def _test_dynamodb(self):
        try:
            ddb = boto3.resource("dynamodb", region_name=AWS_REGION)
            tbl = ddb.Table(TABLE_NAME)
            # Try a lightweight check
            tbl.table_status
            self.dynamodb = ddb
            self.table = tbl
            self.use_dynamodb = True
        except Exception:
            self.use_dynamodb = False
            self.dynamodb = None
            self.table = None

    def get_storage_status(self):
        return {
            "mode": "dynamodb" if self.use_dynamodb else "local_sqlite",
            "table_name": TABLE_NAME,
            "region": AWS_REGION,
            "sqlite_db": DB_PATH,
            "label": f"AWS DynamoDB ({AWS_REGION})" if self.use_dynamodb else "Local ERP Database (SQLite Synced)"
        }

    def _format_sqlite_row(self, row):
        student_id, name, course, email, roll_no, department, year, semester, phone, status, cgpa, attendance, fees_status, fees_total, fees_paid, fees_due, advisor, address, courses_json, grades_json, payments_json, _ = row
        try:
            courses = json.loads(courses_json) if courses_json else []
        except Exception:
            courses = []
        try:
            grades = json.loads(grades_json) if grades_json else []
        except Exception:
            grades = []
        try:
            payments = json.loads(payments_json) if payments_json else []
        except Exception:
            payments = []

        return {
            "studentId": student_id,
            "name": name,
            "course": course,
            "email": email,
            "rollNo": roll_no or f"REG-{student_id}",
            "department": department or "Computer Science",
            "year": year or "3rd Year",
            "semester": semester or "Semester 6",
            "phone": phone or "+1 (555) 000-0000",
            "status": status or "Active",
            "cgpa": round(float(cgpa or 8.0), 2),
            "attendance": round(float(attendance or 85.0), 1),
            "feesStatus": fees_status or "Paid",
            "feesTotal": float(fees_total or 4500.0),
            "feesPaid": float(fees_paid or 4500.0),
            "feesDue": float(fees_due or 0.0),
            "advisor": advisor or "Dr. Alan Vance",
            "address": address or "Campus Residence",
            "courses": courses,
            "grades": grades,
            "payments": payments,
            "timetable": DEFAULT_TIMETABLE,
        }

    def get_all_students(self):
        if self.use_dynamodb and self.table:
            try:
                resp = self.table.scan()
                items = resp.get("Items", [])
                formatted = []
                for item in items:
                    formatted.append(self._normalize_dynamo_item(item))
                formatted.sort(key=lambda x: x.get("name", "").lower())
                return formatted
            except Exception:
                pass  # Fall back to SQLite

        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("SELECT * FROM students ORDER BY LOWER(name) ASC")
        rows = cursor.fetchall()
        conn.close()
        return [self._format_sqlite_row(r) for r in rows]

    def _normalize_dynamo_item(self, item):
        res = dict(item)
        if "courses" in res and isinstance(res["courses"], str):
            try:
                res["courses"] = json.loads(res["courses"])
            except Exception:
                res["courses"] = []
        if "grades" in res and isinstance(res["grades"], str):
            try:
                res["grades"] = json.loads(res["grades"])
            except Exception:
                res["grades"] = []
        if "payments" in res and isinstance(res["payments"], str):
            try:
                res["payments"] = json.loads(res["payments"])
            except Exception:
                res["payments"] = []
        res.setdefault("timetable", DEFAULT_TIMETABLE)
        res["cgpa"] = float(res.get("cgpa", 8.0))
        res["attendance"] = float(res.get("attendance", 85.0))
        res["feesTotal"] = float(res.get("feesTotal", 4500.0))
        res["feesPaid"] = float(res.get("feesPaid", 4500.0))
        res["feesDue"] = float(res.get("feesDue", 0.0))
        return res

    def get_student_by_id(self, student_id):
        all_students = self.get_all_students()
        for s in all_students:
            if s.get("studentId") == student_id:
                return s
        return all_students[0] if all_students else None

    def save_student(self, data):
        student_id = data.get("studentId") or str(uuid.uuid4())[:8]
        name = data.get("name", "").strip()
        course = data.get("course", "").strip()
        email = data.get("email", "").strip()
        department = data.get("department", "Computer Science & Engineering").strip()
        roll_no = data.get("rollNo") or f"2026{department[:2].upper()}{student_id[-4:]}"
        year = data.get("year", "1st Year").strip()
        semester = data.get("semester", "Semester 1").strip()
        phone = data.get("phone", "+1 (555) 234-5678").strip()
        status = data.get("status", "Active")
        
        try:
            cgpa = round(float(data.get("cgpa", 8.5)), 2)
        except (ValueError, TypeError):
            cgpa = 8.5

        try:
            attendance = round(float(data.get("attendance", 88.0)), 1)
        except (ValueError, TypeError):
            attendance = 88.0

        try:
            fees_total = float(data.get("feesTotal", 4500.0))
        except (ValueError, TypeError):
            fees_total = 4500.0

        try:
            fees_paid = float(data.get("feesPaid", fees_total))
        except (ValueError, TypeError):
            fees_paid = fees_total

        fees_due = max(0.0, fees_total - fees_paid)
        fees_status = data.get("feesStatus")
        if not fees_status:
            if fees_due == 0:
                fees_status = "Paid"
            elif fees_paid > 0:
                fees_status = "Partial"
            else:
                fees_status = "Pending"

        advisor = data.get("advisor", "Prof. Alan Vance")
        address = data.get("address", "North University Hall, Campus")
        
        courses = data.get("courses")
        if not courses:
            courses = [
                {"code": "CS-401", "name": course or "Cloud Computing", "credits": 4, "instructor": advisor, "schedule": "Mon, Wed 10:00 AM", "room": "Hall 302", "attendance": int(attendance), "classesTotal": 20, "classesAttended": int(20 * (attendance / 100))},
                {"code": "CS-412", "name": "Modern Web Architectures & APIs", "credits": 3, "instructor": "Prof. David Kim", "schedule": "Mon, Wed 02:00 PM", "room": "Room 204", "attendance": int(attendance), "classesTotal": 20, "classesAttended": int(20 * (attendance / 100))},
            ]

        grades = data.get("grades")
        if not grades:
            grades = [
                {"code": "CS-401", "name": course or "Cloud Computing", "credits": 4, "grade": "A", "points": cgpa, "status": "Passed"},
                {"code": "CS-412", "name": "Modern Web Architectures", "credits": 3, "grade": "A-", "points": max(6.0, cgpa - 0.5), "status": "Passed"},
            ]

        payments = data.get("payments", [])
        if not payments and fees_paid > 0:
            payments = [{
                "receiptId": f"REC-{str(uuid.uuid4())[:6].upper()}",
                "date": datetime.date.today().isoformat(),
                "amount": fees_paid,
                "method": "Online Payment",
                "semester": semester,
                "status": "Completed"
            }]

        record = {
            "studentId": student_id,
            "name": name,
            "course": course,
            "email": email,
            "rollNo": roll_no,
            "department": department,
            "year": year,
            "semester": semester,
            "phone": phone,
            "status": status,
            "cgpa": cgpa,
            "attendance": attendance,
            "feesStatus": fees_status,
            "feesTotal": fees_total,
            "feesPaid": fees_paid,
            "feesDue": fees_due,
            "advisor": advisor,
            "address": address,
            "courses": courses,
            "grades": grades,
            "payments": payments,
        }

        # 1. Save to SQLite
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        self._insert_sqlite_student(cursor, record)
        conn.commit()
        conn.close()

        # 2. Save to DynamoDB if available
        if self.use_dynamodb and self.table:
            try:
                dynamo_record = dict(record)
                dynamo_record["cgpa"] = Decimal(str(cgpa))
                dynamo_record["attendance"] = Decimal(str(attendance))
                dynamo_record["feesTotal"] = Decimal(str(fees_total))
                dynamo_record["feesPaid"] = Decimal(str(fees_paid))
                dynamo_record["feesDue"] = Decimal(str(fees_due))
                dynamo_record["courses"] = json.dumps(courses)
                dynamo_record["grades"] = json.dumps(grades)
                dynamo_record["payments"] = json.dumps(payments)
                self.table.put_item(Item=dynamo_record)
            except Exception:
                pass

        return record

    def update_student(self, student_id, data):
        existing = self.get_student_by_id(student_id)
        if not existing:
            return None
        
        for k, v in data.items():
            if v is not None and v != "":
                existing[k] = v

        if "feesPaid" in data or "feesTotal" in data:
            total = float(existing.get("feesTotal", 4500.0))
            paid = float(existing.get("feesPaid", 0.0))
            due = max(0.0, total - paid)
            existing["feesDue"] = due
            if due == 0:
                existing["feesStatus"] = "Paid"
            elif paid > 0:
                existing["feesStatus"] = "Partial"
            else:
                existing["feesStatus"] = "Pending"

        return self.save_student(existing)

    def delete_student(self, student_id):
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("DELETE FROM students WHERE studentId = ?", (student_id,))
        conn.commit()
        conn.close()

        if self.use_dynamodb and self.table:
            try:
                self.table.delete_item(Key={"studentId": student_id})
            except Exception:
                pass
        return True

    def record_fee_payment(self, student_id, amount, method="Online Gateway", semester=None):
        student = self.get_student_by_id(student_id)
        if not student:
            return None, "Student not found"
        
        amount = float(amount)
        if amount <= 0:
            return None, "Invalid amount"

        current_paid = float(student.get("feesPaid", 0.0))
        new_paid = current_paid + amount
        student["feesPaid"] = new_paid
        total = float(student.get("feesTotal", 4500.0))
        due = max(0.0, total - new_paid)
        student["feesDue"] = due
        if due == 0:
            student["feesStatus"] = "Paid"
        else:
            student["feesStatus"] = "Partial"

        receipt_id = f"REC-{datetime.datetime.now().strftime('%m%d')}-{str(uuid.uuid4())[:4].upper()}"
        payment_record = {
            "receiptId": receipt_id,
            "date": datetime.date.today().isoformat(),
            "time": datetime.datetime.now().strftime("%I:%M %p"),
            "amount": amount,
            "method": method,
            "semester": semester or student.get("semester", "Semester 6"),
            "status": "Completed"
        }
        
        payments = student.get("payments", [])
        payments.insert(0, payment_record)
        student["payments"] = payments

        self.save_student(student)
        return payment_record, None

    def enroll_course(self, student_id, course_code):
        student = self.get_student_by_id(student_id)
        if not student:
            return False, "Student not found"
        
        # Check if already enrolled
        for c in student.get("courses", []):
            if c.get("code") == course_code:
                return False, "Already registered in this course"

        target_course = next((c for c in CATALOG_COURSES if c["code"] == course_code), None)
        if not target_course:
            return False, "Course code not found in catalog"

        new_course_entry = {
            "code": target_course["code"],
            "name": target_course["name"],
            "credits": target_course["credits"],
            "instructor": target_course["instructor"],
            "schedule": target_course["schedule"],
            "room": target_course["room"],
            "attendance": 100,
            "classesTotal": 1,
            "classesAttended": 1,
        }
        courses = student.get("courses", [])
        courses.append(new_course_entry)
        student["courses"] = courses
        self.save_student(student)
        return True, "Enrolled successfully"

    def drop_course(self, student_id, course_code):
        student = self.get_student_by_id(student_id)
        if not student:
            return False, "Student not found"
        
        courses = [c for c in student.get("courses", []) if c.get("code") != course_code]
        if len(courses) == len(student.get("courses", [])):
            return False, "Course was not in your registration list"

        student["courses"] = courses
        self.save_student(student)
        return True, "Course dropped successfully"

    def update_attendance(self, student_id, course_code, attended_delta, total_delta):
        student = self.get_student_by_id(student_id)
        if not student:
            return False, "Student not found"

        found = False
        for c in student.get("courses", []):
            if c.get("code") == course_code:
                c["classesAttended"] = max(0, c.get("classesAttended", 0) + attended_delta)
                c["classesTotal"] = max(1, c.get("classesTotal", 1) + total_delta)
                c["attendance"] = round((c["classesAttended"] / c["classesTotal"]) * 100, 1)
                found = True
                break

        if found:
            # Recalculate overall attendance
            all_att = sum(c.get("classesAttended", 0) for c in student["courses"])
            all_tot = sum(c.get("classesTotal", 1) for c in student["courses"])
            if all_tot > 0:
                student["attendance"] = round((all_att / all_tot) * 100, 1)
            self.save_student(student)
            return True, "Attendance updated"
        return False, "Course not found for this student"

    def get_all_courses(self):
        return CATALOG_COURSES

    def get_all_notices(self):
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("SELECT id, title, category, priority, date, author, content FROM notices ORDER BY created_at DESC")
        rows = cursor.fetchall()
        conn.close()
        return [
            {
                "id": r[0],
                "title": r[1],
                "category": r[2],
                "priority": r[3],
                "date": r[4],
                "author": r[5],
                "content": r[6]
            }
            for r in rows
        ]

    def reset_demo_data(self):
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("DELETE FROM students")
        cursor.execute("DELETE FROM notices")
        for s in SEED_STUDENTS:
            self._insert_sqlite_student(cursor, s)
        for n in CATALOG_NOTICES:
            cursor.execute("""
                INSERT INTO notices (id, title, category, priority, date, author, content)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, (n["id"], n["title"], n["category"], n["priority"], n["date"], n["author"], n["content"]))
        conn.commit()
        conn.close()

        if self.use_dynamodb and self.table:
            try:
                for s in SEED_STUDENTS:
                    self.save_student(s)
            except Exception:
                pass
        return True


storage = StorageManager()
