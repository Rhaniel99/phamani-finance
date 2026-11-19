<?php

namespace App\Services;

use App\Interfaces\Services\IInvitationService;
use App\Interfaces\Services\IShareService;
use App\Models\Contact;
use App\Models\ContactInvitation;
use App\Models\User;
use App\Notifications\ActivityNotification;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class InvitationService implements IInvitationService
{
    public function __construct(
        protected IShareService $shares,
    ) {}

    public function invite(Contact $contact, string $email): ContactInvitation
    {
        $email = mb_strtolower(trim($email));
        $inviter = User::query()->findOrFail($contact->user_id);

        if ($email === mb_strtolower($inviter->email)) {
            throw ValidationException::withMessages(['email' => 'Esse é o seu próprio e-mail.']);
        }

        if ($contact->linked_user_id !== null) {
            throw ValidationException::withMessages(['email' => "{$contact->name} já está vinculado."]);
        }

        return DB::transaction(function () use ($contact, $email, $inviter) {
            // Um convite pendente por contato: o novo substitui o anterior.
            ContactInvitation::query()
                ->where('contact_id', $contact->id)
                ->where('status', 'pending')
                ->update(['status' => 'cancelled']);

            /** @var ContactInvitation $invitation */
            $invitation = ContactInvitation::query()->create([
                'user_id' => $inviter->id,
                'contact_id' => $contact->id,
                'email' => $email,
                'status' => 'pending',
            ]);

            $recipient = User::query()->whereRaw('lower(email) = ?', [$email])->first();
            $recipient?->notify(new ActivityNotification(
                'invitation',
                'Convite de conexão',
                "{$inviter->name} quer dividir contas com você no Phamani.",
                route('inbox'),
            ));

            return $invitation;
        });
    }

    public function pendingFor(User $user): Collection
    {
        return ContactInvitation::query()
            ->with('inviter:id,name,email,avatar')
            ->where('status', 'pending')
            ->whereRaw('lower(email) = ?', [mb_strtolower($user->email)])
            ->where('user_id', '!=', $user->id)
            ->latest()
            ->get();
    }

    public function accept(ContactInvitation $invitation, User $user): void
    {
        $this->ensureRecipient($invitation, $user);

        DB::transaction(function () use ($invitation, $user) {
            /** @var User $inviter */
            $inviter = User::query()->findOrFail($invitation->user_id);

            /** @var Contact $contact */
            $contact = Contact::query()->findOrFail($invitation->contact_id);
            $contact->update(['linked_user_id' => $user->id]);

            // Do lado de quem aceitou: reaproveita um contato já vinculado ou com o mesmo nome; senão cria.
            $mine = Contact::query()->where('user_id', $user->id)->where('linked_user_id', $inviter->id)->first()
                ?? Contact::query()->where('user_id', $user->id)->where('name', $inviter->name)->whereNull('linked_user_id')->first();

            if ($mine !== null) {
                $mine->update(['linked_user_id' => $inviter->id]);
            } else {
                Contact::query()->create([
                    'user_id' => $user->id,
                    'name' => $this->availableName($user->id, $inviter->name),
                    'linked_user_id' => $inviter->id,
                ]);
            }

            // Divisões do mês atual em diante com esse contato (ex.: próximas parcelas) viram pedidos.
            $this->shares->shareUpcomingWith($contact);

            $invitation->update([
                'status' => 'accepted',
                'recipient_user_id' => $user->id,
                'responded_at' => now(),
            ]);

            $inviter->notify(new ActivityNotification(
                'invitation_accepted',
                'Convite aceito',
                "{$user->name} aceitou seu convite. As próximas divisões com ela(e) serão compartilhadas.",
                route('dashboard'),
            ));
        });
    }

    public function decline(ContactInvitation $invitation, User $user): void
    {
        $this->ensureRecipient($invitation, $user);

        $invitation->update([
            'status' => 'declined',
            'recipient_user_id' => $user->id,
            'responded_at' => now(),
        ]);

        User::query()->find($invitation->user_id)?->notify(new ActivityNotification(
            'invitation_declined',
            'Convite recusado',
            "{$user->name} recusou seu convite.",
        ));
    }

    public function unlink(Contact $contact): void
    {
        if ($contact->linked_user_id === null) {
            return;
        }

        DB::transaction(function () use ($contact) {
            Contact::query()
                ->where('user_id', $contact->linked_user_id)
                ->where('linked_user_id', $contact->user_id)
                ->update(['linked_user_id' => null]);

            $contact->update(['linked_user_id' => null]);
        });
    }

    private function ensureRecipient(ContactInvitation $invitation, User $user): void
    {
        // 404 (e não 403) para não revelar convites de outras pessoas.
        abort_unless(
            $invitation->status === 'pending'
                && mb_strtolower($invitation->email) === mb_strtolower($user->email)
                && $invitation->user_id !== $user->id,
            404,
        );
    }

    private function availableName(string $userId, string $name): string
    {
        $candidate = $name;
        $n = 2;

        while (Contact::query()->where('user_id', $userId)->where('name', $candidate)->exists()) {
            $candidate = "{$name} ({$n})";
            $n++;
        }

        return $candidate;
    }
}
