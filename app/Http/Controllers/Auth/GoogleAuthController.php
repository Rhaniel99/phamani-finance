<?php

namespace App\Http\Controllers\Auth;

use App\Http\Controllers\Controller;
use App\Models\User;
use Illuminate\Auth\Events\Registered;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Log;
use Inertia\Inertia;
use Laravel\Socialite\Facades\Socialite;
use Symfony\Component\HttpFoundation\RedirectResponse as SymfonyRedirectResponse;
use Throwable;

class GoogleAuthController extends Controller
{
    /**
     * Envia o usuário para a tela de consentimento do Google.
     */
    public function redirect(): SymfonyRedirectResponse
    {
        return Socialite::driver('google')->redirect();
    }

    /**
     * Recebe o retorno do Google, cria/atualiza o usuário pelo google_id e autentica.
     */
    public function callback(Request $request): RedirectResponse
    {
        try {
            $googleUser = Socialite::driver('google')->user();
        } catch (Throwable $e) {
            Log::warning('Falha no login com Google', ['error' => $e->getMessage()]);

            Inertia::flash('toast', ['type' => 'error', 'message' => 'Não foi possível entrar com o Google. Tente novamente.']);

            return to_route('login');
        }

        if (! $this->isAllowed((string) $googleUser->getEmail())) {
            Log::notice('Login com Google bloqueado (e-mail fora de ALLOWED_EMAILS)', ['email' => $googleUser->getEmail()]);

            Inertia::flash('toast', ['type' => 'error', 'message' => 'Esta conta Google não tem acesso ao Phamani.']);

            return to_route('login');
        }

        $user = User::updateOrCreate(
            ['google_id' => (string) $googleUser->getId()],
            [
                'name' => $googleUser->getName() ?: $googleUser->getNickname() ?: (string) $googleUser->getEmail(),
                'email' => (string) $googleUser->getEmail(),
                'avatar' => $googleUser->getAvatar(),
                'email_verified_at' => now(),
            ],
        );

        if ($user->wasRecentlyCreated) {
            event(new Registered($user));
        }

        Auth::login($user, remember: true);

        $request->session()->regenerate();

        return redirect()->intended(route('dashboard'));
    }

    /**
     * Sem ALLOWED_EMAILS configurado, qualquer conta Google entra (útil em desenvolvimento).
     */
    private function isAllowed(string $email): bool
    {
        /** @var list<string> $allowed */
        $allowed = config('services.google.allowed_emails', []);

        return $allowed === [] || in_array(mb_strtolower(trim($email)), $allowed, true);
    }

    /**
     * Encerra a sessão.
     */
    public function logout(Request $request): RedirectResponse
    {
        Auth::guard('web')->logout();

        $request->session()->invalidate();
        $request->session()->regenerateToken();

        return to_route('login');
    }
}
