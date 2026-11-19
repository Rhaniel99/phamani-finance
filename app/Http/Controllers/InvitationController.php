<?php

namespace App\Http\Controllers;

use App\DTOs\Sharing\InviteContactData;
use App\Interfaces\Services\IInvitationService;
use App\Models\Contact;
use App\Models\ContactInvitation;
use App\Models\User;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Inertia\Inertia;

class InvitationController extends Controller
{
    public function __construct(
        protected IInvitationService $service,
    ) {}

    public function store(Request $request, Contact $contact, InviteContactData $data): RedirectResponse
    {
        abort_unless($contact->user_id === (string) $request->user()?->getAuthIdentifier(), 404);

        $this->service->invite($contact, $data->email);

        Inertia::flash('toast', [
            'type' => 'success',
            'message' => "Convite enviado. Quando {$contact->name} entrar no Phamani com {$data->email}, o convite vai aparecer em Pendências.",
        ]);

        return back();
    }

    public function unlink(Request $request, Contact $contact): RedirectResponse
    {
        abort_unless($contact->user_id === (string) $request->user()?->getAuthIdentifier(), 404);

        $this->service->unlink($contact);

        Inertia::flash('toast', ['type' => 'success', 'message' => "Vínculo com {$contact->name} desfeito."]);

        return back();
    }

    public function accept(Request $request, ContactInvitation $invitation): RedirectResponse
    {
        $this->service->accept($invitation, $this->user($request));

        Inertia::flash('toast', ['type' => 'success', 'message' => 'Convite aceito!']);

        return back();
    }

    public function decline(Request $request, ContactInvitation $invitation): RedirectResponse
    {
        $this->service->decline($invitation, $this->user($request));

        Inertia::flash('toast', ['type' => 'success', 'message' => 'Convite recusado.']);

        return back();
    }

    private function user(Request $request): User
    {
        /** @var User */
        return $request->user();
    }
}
