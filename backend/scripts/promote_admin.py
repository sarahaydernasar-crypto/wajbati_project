import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))


def main() -> None:
    from sqlmodel import Session, select

    from src.waj_be.database import create_db, engine
    from src.waj_be.models import OwnerApplication, OwnerApplicationStatus, User, UserRole, utc_now

    create_db()
    phone_number = input("Enter the existing account phone in +964 format: ").strip()
    confirmation = input(f"Promote {phone_number} to admin? Type yes to continue: ").strip()
    if confirmation.lower() != "yes":
        print("Cancelled.")
        return

    with Session(engine) as session:
        user = session.exec(select(User).where(User.phone_number == phone_number)).first()
        if user is None:
            print("No account found. Register this phone first, then run the script again.")
            return

        user.role = UserRole.ADMIN
        user.is_active = True
        application = session.exec(
            select(OwnerApplication).where(OwnerApplication.user_id == user.id)
        ).first()
        if application is not None and application.status == OwnerApplicationStatus.PENDING:
            application.status = OwnerApplicationStatus.REJECTED
            application.reviewed_at = utc_now()
            application.reviewed_by_id = user.id
            session.add(application)

        session.add(user)
        session.commit()
        print("Admin role assigned. Log in again to get a token with the new role.")


if __name__ == "__main__":
    main()
