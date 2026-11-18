<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Socialite\Facades\Socialite;
use Laravel\Socialite\Two\User as SocialiteUser;
use Mockery;
use Tests\TestCase;

class GoogleAuthTest extends TestCase
{
    use RefreshDatabase;

    private function fakeGoogleUser(string $id = '1234567890', string $email = 'ana@gmail.com'): void
    {
        $googleUser = (new SocialiteUser)->map([
            'id' => $id,
            'name' => 'Ana Souza',
            'email' => $email,
            'avatar' => 'https://lh3.googleusercontent.com/a/avatar',
        ]);

        $provider = Mockery::mock('Laravel\Socialite\Contracts\Provider');
        $provider->shouldReceive('user')->andReturn($googleUser);

        Socialite::shouldReceive('driver')->with('google')->andReturn($provider);
    }

    public function test_login_page_is_rendered_for_guests(): void
    {
        $this->get('/')->assertOk();
    }

    public function test_guests_are_redirected_to_login(): void
    {
        $this->get(route('dashboard'))->assertRedirect(route('login'));
    }

    public function test_first_google_login_creates_user_with_default_data(): void
    {
        $this->fakeGoogleUser();

        $this->get(route('auth.google.callback'))->assertRedirect(route('dashboard'));

        $user = User::where('google_id', '1234567890')->firstOrFail();

        $this->assertAuthenticatedAs($user);
        $this->assertSame('ana@gmail.com', $user->email);
        $this->assertSame(1, $user->accounts()->count());
        $this->assertSame(7, $user->categories()->count());
    }

    public function test_next_logins_reuse_the_same_user(): void
    {
        $this->fakeGoogleUser();
        $this->get(route('auth.google.callback'));
        $this->post(route('logout'));

        $this->fakeGoogleUser();
        $this->get(route('auth.google.callback'));

        $this->assertSame(1, User::count());
        $this->assertSame(1, User::first()->accounts()->count());
    }

    public function test_user_can_logout(): void
    {
        $this->actingAs(User::factory()->create())
            ->post(route('logout'))
            ->assertRedirect(route('login'));

        $this->assertGuest();
    }
}
